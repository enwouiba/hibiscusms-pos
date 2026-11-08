import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/printer_service.dart';
import '../data/sunmi_printer_adapter.dart';

export '../data/printer_service.dart' show BluetoothPrinterDevice, ReceiptData, ReceiptItem;

enum PrinterMode {
  sunmiIntegrated('sunmi', 'SUNMI Entegre'),
  bluetooth('bluetooth', 'Bluetooth ESC/POS');

  final String code;
  final String label;
  const PrinterMode(this.code, this.label);

  static PrinterMode fromCode(String? c) =>
      PrinterMode.values.firstWhere((m) => m.code == c, orElse: () => PrinterMode.bluetooth);
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
    final isSunmi = await SunmiPrinterAdapter.instance.isSunmiDevice();
    state = state.copyWith(
      isSunmiDetected: isSunmi,
      mode: isSunmi ? PrinterMode.sunmiIntegrated : PrinterMode.bluetooth,
    );
    if (isSunmi) {
      await SunmiPrinterAdapter.instance.bindPrinter();
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
