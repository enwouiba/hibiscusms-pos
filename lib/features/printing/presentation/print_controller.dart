import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/printer_service.dart';
import '../data/sunmi_printer_adapter.dart';

export '../data/printer_service.dart' show BluetoothPrinterDevice, ReceiptData, ReceiptItem;

enum PrinterMode {
  sunmiIntegrated('sunmi', 'SUNMI Entegre'),
  bluetooth('bluetooth', 'Bluetooth ESC/POS'),
  usb('usb', 'USB / Aparèy (ESC/POS)'),
  network('network', 'Rezo (TCP 9100)'),
  cups('cups', 'Sistèm / CUPS (lp)');

  final String code;
  final String label;
  const PrinterMode(this.code, this.label);

  static PrinterMode fromCode(String? c) =>
      PrinterMode.values.firstWhere((m) => m.code == c, orElse: () => PrinterMode.bluetooth);

  /// Transpò desktop ki voye byte brit (pa Bluetooth, pa SUNMI).
  bool get isDesktopTransport =>
      this == PrinterMode.usb || this == PrinterMode.network || this == PrinterMode.cups;
}

/// Èske n ap kouri sou yon òdinatè (Linux/Windows/macOS)?
bool get _isDesktop {
  try {
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}

class PrintState {
  const PrintState({
    this.isPrinting = false,
    this.lastError,
    this.connectedAddress,
    this.mode = PrinterMode.bluetooth,
    this.isSunmiDetected = false,
  });
  final bool isPrinting;
  final String? lastError;
  final String? connectedAddress;
  final PrinterMode mode;
  final bool isSunmiDetected;

  PrintState copyWith({
    bool? isPrinting,
    String? lastError,
    String? connectedAddress,
    PrinterMode? mode,
    bool? isSunmiDetected,
    bool clearError = false,
  }) =>
      PrintState(
        isPrinting: isPrinting ?? this.isPrinting,
        lastError: clearError ? null : (lastError ?? this.lastError),
        connectedAddress: connectedAddress ?? this.connectedAddress,
        mode: mode ?? this.mode,
        isSunmiDetected: isSunmiDetected ?? this.isSunmiDetected,
      );
}

class PrintController extends Notifier<PrintState> {
  @override
  PrintState build() {
    _detectSunmi();
    return const PrintState();
  }

  Future<void> _detectSunmi() async {
    bool isSunmi = false;
    try {
      isSunmi = await SunmiPrinterAdapter.instance.isSunmiDevice();
    } catch (_) {
      isSunmi = false; // SUNMI se Android sèlman — sou desktop li pa la
    }
    // Defo entelijan: SUNMI machin → SUNMI; òdinatè → USB; telefòn → Bluetooth.
    final defaultMode = isSunmi
        ? PrinterMode.sunmiIntegrated
        : (_isDesktop ? PrinterMode.usb : PrinterMode.bluetooth);
    state = state.copyWith(isSunmiDetected: isSunmi, mode: defaultMode);
    if (isSunmi) {
      await SunmiPrinterAdapter.instance.bindPrinter();
    }
  }

  /// Voye byte yo sou transpò desktop la selon mòd + konfigirasyon ki sove.
  Future<bool> _sendDesktop(List<int> bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final svc = PrinterService.instance;
    switch (state.mode) {
      case PrinterMode.usb:
        final path = prefs.getString('printer_device_path') ?? '/dev/usb/lp0';
        return svc.printBytesDevice(bytes, path);
      case PrinterMode.network:
        final host = prefs.getString('printer_host') ?? '';
        final port = prefs.getInt('printer_port') ?? 9100;
        if (host.trim().isEmpty) return false;
        return svc.printBytesNetwork(bytes, host.trim(), port);
      case PrinterMode.cups:
        return svc.printBytesCups(bytes, printerName: prefs.getString('printer_cups_name'));
      default:
        return false;
    }
  }

  void setMode(PrinterMode mode) {
    state = state.copyWith(mode: mode);
  }

  Future<bool> _ensurePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    await Permission.bluetooth.request();
    final location = await Permission.locationWhenInUse.request();
    final modernOk = scan.isGranted && connect.isGranted;
    final legacyOk = location.isGranted;
    return modernOk || legacyOk;
  }

  Future<Map<String, String>> diagnose() async {
    final isSunmi = state.isSunmiDetected;
    final btEnabled = await PrinterService.instance.isBluetoothEnabled();
    final paired = await PrinterService.instance.pairedDevices().catchError(
          (e) => <BluetoothPrinterDevice>[],
        );
    return {
      'Mòd': state.mode.label,
      'SUNMI detekte': isSunmi ? 'Wi' : 'Non',
      'Bluetooth aktif': btEnabled ? 'Wi' : 'Non',
      'Aparèy Bluetooth peyè': paired.length.toString(),
    };
  }

  Future<List<BluetoothPrinterDevice>> scanPaired() async {
    final ok = await _ensurePermissions();
    if (!ok) return [];
    return PrinterService.instance.pairedDevices();
  }

  Future<bool> connect(BluetoothPrinterDevice device) async {
    final ok = await _ensurePermissions();
    if (!ok) return false;
    final success = await PrinterService.instance.connect(device.address);
    if (success) {
      state = state.copyWith(connectedAddress: device.address);
    }
    return success;
  }

  Future<bool> testPrint({String? savedAddress}) async {
    if (state.mode == PrinterMode.sunmiIntegrated) {
      return SunmiPrinterAdapter.instance.printTest();
    }
    // USB / Rezo / CUPS — voye byte brit, pa bezwen Bluetooth
    if (state.mode.isDesktopTransport) {
      final bytes = await PrinterService.instance.buildTestBytes();
      return _sendDesktop(bytes);
    }
    if (!await _ensurePermissions()) return false;
    final connected = await PrinterService.instance.isConnected();
    if (!connected) {
      if (savedAddress == null) return false;
      final ok = await PrinterService.instance.connect(savedAddress);
      if (!ok) return false;
    }
    return PrinterService.instance.printTest();
  }

  Future<bool> printReceipt(ReceiptData data, {String? savedAddress}) async {
    state = state.copyWith(isPrinting: true, clearError: true);
    try {
      // SUNMI: imprimant entegre — pa bezwen Bluetooth
      if (state.mode == PrinterMode.sunmiIntegrated) {
        final ok = await SunmiPrinterAdapter.instance.printReceipt(data);
        state = state.copyWith(isPrinting: false);
        if (!ok) {
          state = state.copyWith(lastError: 'Pa kapab enprime sou SUNMI');
        }
        return ok;
      }

      // USB / Rezo / CUPS — transpò desktop (byte brit)
      if (state.mode.isDesktopTransport) {
        final bytes = await PrinterService.instance.buildReceiptBytes(data);
        final ok = await _sendDesktop(bytes);
        state = state.copyWith(
          isPrinting: false,
          lastError: ok ? null : 'Pa kapab enprime (${state.mode.label}) — verifye konfigirasyon/pèmisyon',
        );
        return ok;
      }

      // Bluetooth ESC/POS
      if (!await _ensurePermissions()) {
        state = state.copyWith(isPrinting: false, lastError: 'Pèmisyon Bluetooth refize');
        return false;
      }
      final connected = await PrinterService.instance.isConnected();
      if (!connected) {
        if (savedAddress == null) {
          state = state.copyWith(isPrinting: false, lastError: 'Pa gen printer konfigire');
          return false;
        }
        final ok = await PrinterService.instance.connect(savedAddress);
        if (!ok) {
          state = state.copyWith(isPrinting: false, lastError: 'Pa kapab konekte ak printer la');
          return false;
        }
      }
      final ok = await PrinterService.instance.printReceipt(data);
      state = state.copyWith(isPrinting: false);
      return ok;
    } catch (e) {
      state = state.copyWith(isPrinting: false, lastError: e.toString());
      return false;
    }
  }
}

final printStateProvider =
    NotifierProvider<PrintController, PrintState>(PrintController.new);
