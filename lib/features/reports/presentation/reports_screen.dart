import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/di/providers.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_formatter.dart';

// ============================================================
// Modèl
// ============================================================

class DateRange {
  final DateTime from;
  final DateTime to;
  final String label;
  const DateRange({required this.from, required this.to, required this.label});

  static DateRange today() {
    final n = DateTime.now();
    return DateRange(
      from: DateTime(n.year, n.month, n.day),
      to: DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: 'Jodi a',
    );
  }

  static DateRange yesterday() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return DateRange(
      from: DateTime(y.year, y.month, y.day),
      to: DateTime(y.year, y.month, y.day, 23, 59, 59),
      label: 'Yè',
    );
  }

  static DateRange last7Days() {
    final n = DateTime.now();
    return DateRange(
      from: DateTime(n.year, n.month, n.day).subtract(const Duration(days: 6)),
      to: DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: '7 jou',
    );
  }

  static DateRange last30Days() {
    final n = DateTime.now();
    return DateRange(
      from: DateTime(n.year, n.month, n.day).subtract(const Duration(days: 29)),
      to: DateTime(n.year, n.month, n.day, 23, 59, 59),
      label: '30 jou',
    );
  }

  static DateRange thisMonth() {
    final n = DateTime.now();
    return DateRange(
      from: DateTime(n.year, n.month, 1),
      to: DateTime(n.year, n.month + 1, 0, 23, 59, 59),
      label: 'Mwa sa',
    );
  }

  static DateRange lastMonth() {
    final n = DateTime.now();
    return DateRange(
      from: DateTime(n.year, n.month - 1, 1),
      to: DateTime(n.year, n.month, 0, 23, 59, 59),
      label: 'Mwa pase',
    );
  }
}

class DashboardData {
  final double revenue;
  final double cogs; // pri pwopriyetè (cost of goods sold)
  final double grossProfit;
  final double profitMargin;
  final int salesCount;
  final double averageSale;
  final double previousRevenue; // pou konparezon
  final double revenueDelta;
  final List<DailyPoint> dailySeries;
  final List<TopProduct> topProducts;
  final List<TopCustomer> topCustomers;
  final List<PaymentBreakdown> paymentBreakdown;
  final int lowStockCount;
  final double totalStockValue;
  final double totalStockUnits;
  final int productCount;
  final double cashSalesTotal;
  final int refundedCount;
  final double refundedTotal;

  DashboardData({
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.profitMargin,
    required this.salesCount,
    required this.averageSale,
    required this.previousRevenue,
    required this.revenueDelta,
    required this.dailySeries,
    required this.topProducts,
    required this.topCustomers,
    required this.paymentBreakdown,
    required this.lowStockCount,
    required this.totalStockValue,
    required this.totalStockUnits,
    required this.productCount,
    required this.cashSalesTotal,
    required this.refundedCount,
    required this.refundedTotal,
  });
}

class DailyPoint {
  final DateTime day;
  final double revenue;
  final double profit;
  final int count;
  DailyPoint(this.day, this.revenue, this.profit, this.count);
}

class TopProduct {
  final String name;
  final double qty;
  final double revenue;
  final double profit;
  TopProduct(this.name, this.qty, this.revenue, this.profit);
}

class TopCustomer {
  final String name;
  final double total;
  final int count;
  TopCustomer(this.name, this.total, this.count);
}

class PaymentBreakdown {
  final String method;
  final String label;
  final double total;
  PaymentBreakdown(this.method, this.label, this.total);

  static String labelFor(String code) => switch (code) {
        'cash' => 'Kach',
        'mon_cash' => 'Moncash',
        'natcash' => 'Natcash',
        'card' => 'Kat',
        'bank_transfer' => 'Vire bank',
        'credit' => 'Kredite',
        'check' => 'Chèk',
        _ => code,
      };
}

// ============================================================
// Provider
// ============================================================

final _dateRangeProvider = StateProvider<DateRange>((ref) => DateRange.today());

final _dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  final db = ref.watch(databaseProvider).requireValue;
  final range = ref.watch(_dateRangeProvider);
  if (storeId == null) {
    return _empty();
  }
  return _loadDashboard(db, storeId, range);
});

DashboardData _empty() => DashboardData(
      revenue: 0, cogs: 0, grossProfit: 0, profitMargin: 0,
      salesCount: 0, averageSale: 0, previousRevenue: 0, revenueDelta: 0,
      dailySeries: const [], topProducts: const [], topCustomers: const [],
      paymentBreakdown: const [], lowStockCount: 0, totalStockValue: 0,
      totalStockUnits: 0, productCount: 0, cashSalesTotal: 0,
      refundedCount: 0, refundedTotal: 0,
    );

Future<DashboardData> _loadDashboard(Database db, String storeId, DateRange range) async {
  final fromStr = range.from.toUtc().toIso8601String();
  final toStr = range.to.toUtc().toIso8601String();

  // 1. Revni (kob KI REYÈLMAN antre — enkli peman pasyèl sou kredit)
  //    Kantite vant konte tout (completed + credit)
  final revenueRow = await db.rawQuery('''
    SELECT
      COALESCE(SUM(amount_received), 0) AS revenue,
      COUNT(*) AS sales_count
    FROM sales
    WHERE store_id = ? AND status IN ('completed', 'credit') AND deleted_at IS NULL
      AND created_at >= ? AND created_at <= ?
  ''', [storeId, fromStr, toStr]);
  final salesRevenue = (revenueRow.first['revenue'] as num?)?.toDouble() ?? 0;
  final salesCount = ((revenueRow.first['sales_count'] as num?) ?? 0).toInt();

  // Ajoute peman dèt (kliyan ki peye ansyen dèt) — konsistan ak home
  final debtPayRow = await db.rawQuery('''
    SELECT COALESCE(SUM(amount), 0) AS paid
    FROM customer_payments
    WHERE (store_id = ? OR store_id IS NULL)
      AND type = 'payment'
      AND created_at >= ? AND created_at <= ?
  ''', [storeId, fromStr, toStr]);
  final debtRevenue = (debtPayRow.first['paid'] as num?)?.toDouble() ?? 0;
  final revenue = salesRevenue + debtRevenue;

  // COGS separe (kalkile sou sale_items sèl)
  final cogsRow = await db.rawQuery('''
    SELECT COALESCE(SUM(si.cost_snapshot * si.quantity), 0) AS cogs
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    WHERE s.store_id = ? AND s.status = 'completed' AND s.deleted_at IS NULL
      AND s.created_at >= ? AND s.created_at <= ?
  ''', [storeId, fromStr, toStr]);
  final cogs = (cogsRow.first['cogs'] as num?)?.toDouble() ?? 0;
  final grossProfit = revenue - cogs;
  final profitMargin = revenue > 0 ? (grossProfit / revenue * 100) : 0;
  final averageSale = salesCount > 0 ? (revenue / salesCount) : 0;

  // 2. Konparezon ak peryòd pase a
  final periodLength = range.to.difference(range.from);
  final prevFrom = range.from.subtract(periodLength + const Duration(seconds: 1)).toUtc().toIso8601String();
  final prevTo = range.from.subtract(const Duration(seconds: 1)).toUtc().toIso8601String();
  final prevRow = await db.rawQuery('''
    SELECT COALESCE(SUM(amount_received), 0) AS revenue
    FROM sales WHERE store_id = ? AND status IN ('completed', 'credit')
      AND deleted_at IS NULL
      AND created_at >= ? AND created_at <= ?
  ''', [storeId, prevFrom, prevTo]);
  final prevDebtRow = await db.rawQuery('''
    SELECT COALESCE(SUM(amount), 0) AS paid
    FROM customer_payments
    WHERE (store_id = ? OR store_id IS NULL)
      AND type = 'payment'
      AND created_at >= ? AND created_at <= ?
  ''', [storeId, prevFrom, prevTo]);
  final previousRevenue = ((prevRow.first['revenue'] as num?)?.toDouble() ?? 0)
    + ((prevDebtRow.first['paid'] as num?)?.toDouble() ?? 0);
  final revenueDelta = previousRevenue > 0
      ? ((revenue - previousRevenue) / previousRevenue * 100)
      : (revenue > 0 ? 100.0 : 0.0);

  // 3. Seri pa jou
  final seriesRows = await db.rawQuery('''
    -- Sub-query: konte revni pa jou sou sales sèl (san JOIN — evite duplikasyon)
    SELECT day,
           COALESCE(SUM(revenue), 0) AS revenue,
           COALESCE(SUM(profit), 0) AS profit,
           COALESCE(SUM(count), 0) AS count
    FROM (
      SELECT DATE(created_at) AS day,
             total AS revenue,
             0 AS profit,  -- kalkile apre nan subquery
             1 AS count
      FROM sales
      WHERE store_id = ? AND status = 'completed' AND deleted_at IS NULL
        AND created_at >= ? AND created_at <= ?
      UNION ALL
      SELECT DATE(s.created_at) AS day,
             0 AS revenue,
             (si.subtotal - (si.cost_snapshot * si.quantity)) AS profit,
             0 AS count
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.store_id = ? AND s.status = 'completed' AND s.deleted_at IS NULL
        AND s.created_at >= ? AND s.created_at <= ?
    ) t
    GROUP BY day
    ORDER BY day
  ''', [storeId, fromStr, toStr, storeId, fromStr, toStr]);
  final dailySeries = seriesRows.map((r) => DailyPoint(
        DateTime.parse(r['day'] as String),
        (r['revenue'] as num).toDouble(),
        (r['profit'] as num).toDouble(),
        ((r['count'] as num?) ?? 0).toInt(),
      )).toList();

  // 4. Top pwodwi
  final topRows = await db.rawQuery('''
    SELECT si.name_snapshot AS name,
           SUM(si.quantity) AS qty,
           SUM(si.subtotal) AS revenue,
           SUM(si.subtotal - (si.cost_snapshot * si.quantity)) AS profit
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    WHERE s.store_id = ? AND s.status = 'completed' AND s.deleted_at IS NULL
      AND s.created_at >= ? AND s.created_at <= ?
    GROUP BY si.name_snapshot
    ORDER BY revenue DESC
    LIMIT 5
  ''', [storeId, fromStr, toStr]);
  final topProducts = topRows.map((r) => TopProduct(
        r['name'] as String,
        (r['qty'] as num).toDouble(),
        (r['revenue'] as num).toDouble(),
        (r['profit'] as num).toDouble(),
      )).toList();

  // 5. Top kliyan
  final custRows = await db.rawQuery('''
    SELECT COALESCE(c.name, 'Pa gen kliyan') AS name,
           SUM(s.total) AS total,
           COUNT(*) AS count
    FROM sales s
    LEFT JOIN customers c ON c.id = s.customer_id
    WHERE s.store_id = ? AND s.status = 'completed' AND s.deleted_at IS NULL
      AND s.created_at >= ? AND s.created_at <= ?
    GROUP BY c.id, c.name
    ORDER BY total DESC
    LIMIT 5
  ''', [storeId, fromStr, toStr]);
  final topCustomers = custRows.map((r) => TopCustomer(
        r['name'] as String,
        (r['total'] as num).toDouble(),
        ((r['count'] as num?) ?? 0).toInt(),
      )).toList();

  // 6. Mwayen peman
  final payRows = await db.rawQuery('''
    SELECT p.method AS method, SUM(p.amount) AS total
    FROM payments p
    JOIN sales s ON s.id = p.sale_id
    WHERE s.store_id = ? AND s.status = 'completed' AND s.deleted_at IS NULL
      AND s.created_at >= ? AND s.created_at <= ?
    GROUP BY p.method
    ORDER BY total DESC
  ''', [storeId, fromStr, toStr]);
  final paymentBreakdown = payRows.map((r) => PaymentBreakdown(
        r['method'] as String,
        PaymentBreakdown.labelFor(r['method'] as String),
        (r['total'] as num).toDouble(),
      )).toList();
  final cashSalesTotal = paymentBreakdown
      .where((p) => p.method == 'cash')
      .fold<double>(0, (s, p) => s + p.total);

  // 7. Refunded/cancelled
  final refundRow = await db.rawQuery('''
    SELECT COUNT(*) AS cnt, COALESCE(SUM(total), 0) AS total
    FROM sales
    WHERE store_id = ? AND status IN ('refunded','cancelled')
      AND created_at >= ? AND created_at <= ?
  ''', [storeId, fromStr, toStr]);
  final refundedCount = ((refundRow.first['cnt'] as num?) ?? 0).toInt();
  final refundedTotal = (refundRow.first['total'] as num?)?.toDouble() ?? 0;

  // 8. Stock
  final stockRow = await db.rawQuery('''
    SELECT
      COUNT(*) AS product_count,
      COALESCE(SUM(p.cost * ps.stock), 0) AS stock_value,
      COALESCE(SUM(ps.stock), 0) AS stock_units,
      SUM(CASE WHEN ps.stock <= ps.low_stock_alert THEN 1 ELSE 0 END) AS low_count
    FROM products p
    JOIN product_stocks ps ON ps.product_id = p.id AND ps.store_id = ?
    WHERE p.is_active = 1
  ''', [storeId]);

  return DashboardData(
    revenue: revenue,
    cogs: cogs,
    grossProfit: grossProfit,
    profitMargin: profitMargin.toDouble(),
    salesCount: salesCount,
    averageSale: averageSale.toDouble(),
    previousRevenue: previousRevenue,
    revenueDelta: revenueDelta,
    dailySeries: dailySeries,
    topProducts: topProducts,
    topCustomers: topCustomers,
    paymentBreakdown: paymentBreakdown,
    lowStockCount: ((stockRow.first['low_count'] as num?) ?? 0).toInt(),
    totalStockValue: (stockRow.first['stock_value'] as num?)?.toDouble() ?? 0,
    totalStockUnits: (stockRow.first['stock_units'] as num?)?.toDouble() ?? 0,
    productCount: ((stockRow.first['product_count'] as num?) ?? 0).toInt(),
    cashSalesTotal: cashSalesTotal,
    refundedCount: refundedCount,
    refundedTotal: refundedTotal,
  );
}

// ============================================================
// UI
// ============================================================

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_dashboardProvider);
    final range = ref.watch(_dateRangeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_dashboardProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_dashboardProvider),
        child: data.when(
          data: (d) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _DateRangeChips(current: range),
              const SizedBox(height: 8),
              _RangeHeader(range: range),
              const SizedBox(height: 12),
              _MainKpiCards(data: d, range: range),
              const SizedBox(height: 12),
              _ProfitLossCard(data: d),
              const SizedBox(height: 12),
              _StockCard(data: d),
              const SizedBox(height: 12),
              if (d.dailySeries.length > 1) _SalesChartCard(data: d),
              if (d.dailySeries.length > 1) const SizedBox(height: 12),
              if (d.paymentBreakdown.isNotEmpty) _PaymentChartCard(data: d),
              if (d.paymentBreakdown.isNotEmpty) const SizedBox(height: 12),
              _TopProductsCard(data: d),
              const SizedBox(height: 12),
              _TopCustomersCard(data: d),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Erè: $e'),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateRangeChips extends ConsumerWidget {
  const _DateRangeChips({required this.current});
  final DateRange current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = [
      ('Jodi a', DateRange.today()),
      ('Yè', DateRange.yesterday()),
      ('7 jou', DateRange.last7Days()),
      ('30 jou', DateRange.last30Days()),
      ('Mwa sa', DateRange.thisMonth()),
      ('Mwa pase', DateRange.lastMonth()),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...options.map((o) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(o.$1),
                  selected: current.label == o.$1,
                  onSelected: (_) => ref.read(_dateRangeProvider.notifier).state = o.$2,
                ),
              )),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: const Text('Pèsonalize'),
              onPressed: () async {
                final result = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: DateTimeRange(
                    start: current.from,
                    end: current.to,
                  ),
                );
                if (result != null && context.mounted) {
                  ref.read(_dateRangeProvider.notifier).state = DateRange(
                    from: result.start,
                    to: DateTime(result.end.year, result.end.month, result.end.day, 23, 59, 59),
                    label: 'Pèsonalize',
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeHeader extends StatelessWidget {
  const _RangeHeader({required this.range});
  final DateRange range;
  @override
  Widget build(BuildContext context) {
    final isSame = range.from.year == range.to.year &&
        range.from.month == range.to.month &&
        range.from.day == range.to.day;
    final text = isSame
        ? DateFormatter.dayOnly(range.from)
        : '${DateFormatter.dayOnly(range.from)} → ${DateFormatter.dayOnly(range.to)}';
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _MainKpiCards extends StatelessWidget {
  const _MainKpiCards({required this.data, required this.range});
  final DashboardData data;
  final DateRange range;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Revni — pi gwo kat
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text('REVNI ${range.label.toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  MoneyFormatter.format(data.revenue),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      data.revenueDelta >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: data.revenueDelta >= 0 ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${data.revenueDelta >= 0 ? '+' : ''}${data.revenueDelta.toStringAsFixed(1)}% vs peryòd anvan',
                      style: TextStyle(
                        color: data.revenueDelta >= 0 ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _MiniKpi(
              icon: Icons.receipt,
              label: 'Vant',
              value: data.salesCount.toString(),
              color: Colors.blue,
            )),
            const SizedBox(width: 8),
            Expanded(child: _MiniKpi(
              icon: Icons.calculate,
              label: 'Mwayèn / vant',
              value: MoneyFormatter.format(data.averageSale),
              color: Colors.purple,
            )),
          ],
        ),
      ],
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)))]),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ProfitLossCard extends StatelessWidget {
  const _ProfitLossCard({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) {
    final isLoss = data.grossProfit < 0;
    final color = isLoss ? Colors.red : Colors.green;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isLoss ? Icons.warning : Icons.trending_up, color: color),
                const SizedBox(width: 8),
                Text(isLoss ? 'PÈT' : 'BENEFIS BRIT',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${data.profitMargin.toStringAsFixed(1)}%',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  backgroundColor: color.withValues(alpha: 0.1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              MoneyFormatter.format(data.grossProfit.abs()),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 12),
            const Divider(),
            _row('Revni', MoneyFormatter.format(data.revenue), bold: true),
            _row('— Pri acha (COGS)', MoneyFormatter.format(data.cogs)),
            _row('= ${isLoss ? "Pèt" : "Benefis"}', MoneyFormatter.format(data.grossProfit),
                bold: true, color: color),
            if (data.refundedCount > 0) ...[
              const Divider(),
              _row('Vant anile/ranbouse (${data.refundedCount})',
                  MoneyFormatter.format(data.refundedTotal), color: Colors.orange),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : null,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2, color: Colors.indigo),
                SizedBox(width: 8),
                Text('ENVANTÈ STOCK', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Valè total stock', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(
                        MoneyFormatter.format(data.totalStockValue),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pwodwi total', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(
                        data.productCount.toString(),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Inite total', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(
                        data.totalStockUnits.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (data.lowStockCount > 0)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stock ba', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${data.lowStockCount} pwodwi',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesChartCard extends StatelessWidget {
  const _SalesChartCard({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    final profitSpots = <FlSpot>[];
    for (int i = 0; i < data.dailySeries.length; i++) {
      spots.add(FlSpot(i.toDouble(), data.dailySeries[i].revenue));
      profitSpots.add(FlSpot(i.toDouble(), data.dailySeries[i].profit));
    }
    final maxY = data.dailySeries.fold<double>(0,
        (m, p) => p.revenue > m ? p.revenue : m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart, color: Colors.blue),
                SizedBox(width: 8),
                Text('VANT PA JOU', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _legend(Colors.blue, 'Revni'),
                const SizedBox(width: 12),
                _legend(Colors.green, 'Benefis'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY * 1.2,
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (v, _) => Text(
                          v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: (data.dailySeries.length / 5).ceilToDouble().clamp(1, 99),
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= data.dailySeries.length) return const SizedBox.shrink();
                          final d = data.dailySeries[i].day;
                          return Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withValues(alpha: 0.15),
                      ),
                    ),
                    LineChartBarData(
                      spots: profitSpots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _PaymentChartCard extends StatelessWidget {
  const _PaymentChartCard({required this.data});
  final DashboardData data;

  static const _colors = [
    Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFFFF9800),
    Color(0xFF9C27B0), Color(0xFFF44336), Color(0xFF00BCD4), Color(0xFF795548),
  ];

  @override
  Widget build(BuildContext context) {
    final total = data.paymentBreakdown.fold<double>(0, (s, p) => s + p.total);
    if (total <= 0) return const SizedBox.shrink();
    final sections = <PieChartSectionData>[];
    for (int i = 0; i < data.paymentBreakdown.length; i++) {
      final p = data.paymentBreakdown[i];
      sections.add(PieChartSectionData(
        value: p.total,
        title: '${(p.total / total * 100).toStringAsFixed(0)}%',
        color: _colors[i % _colors.length],
        radius: 70,
        titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('MWAYEN PEMAN', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: PieChart(
                    PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 30),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: data.paymentBreakdown.asMap().entries.map((e) {
                      final p = e.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, color: _colors[e.key % _colors.length]),
                            const SizedBox(width: 6),
                            Expanded(child: Text(p.label, style: const TextStyle(fontSize: 12))),
                            Text(MoneyFormatter.format(p.total),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.star, color: Colors.amber),
                SizedBox(width: 8),
                Text('TOP 5 PWODWI', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (data.topProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Pa gen vant nan peryòd la.'),
              )
            else
              ...data.topProducts.asMap().entries.map((e) {
                final p = e.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 12, child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${p.qty.toStringAsFixed(0)} vandi • Benefis: ${MoneyFormatter.format(p.profit)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(MoneyFormatter.format(p.revenue),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _TopCustomersCard extends StatelessWidget {
  const _TopCustomersCard({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.people, color: Colors.teal),
                SizedBox(width: 8),
                Text('TOP 5 KLIYAN', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (data.topCustomers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Pa gen kliyan ki vann nan peryòd la.'),
              )
            else
              ...data.topCustomers.asMap().entries.map((e) {
                final c = e.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.teal,
                        child: Text('${e.key + 1}',
                            style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${c.count} vant',
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(MoneyFormatter.format(c.total),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
