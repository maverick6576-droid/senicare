import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:senicare/screens/admin/admin_lean_startup_tab.dart';

class AdminDashboard extends StatelessWidget {
  final FirebaseFirestore? firestore;
  const AdminDashboard({super.key, this.firestore});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Panel', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => DependencyInjection.auth.signOut(),
            )
          ],
          bottom: const TabBar(
            labelColor: Colors.red,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.red,
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.rocket_launch), text: 'Lean Startup'),
              Tab(icon: Icon(Icons.attach_money), text: 'Finanzas'),
              Tab(icon: Icon(Icons.verified_user), text: 'Validaciones'),
              Tab(icon: Icon(Icons.gavel), text: 'Disputas'),
              Tab(icon: Icon(Icons.people), text: 'Usuarios'),
              Tab(icon: Icon(Icons.security), text: 'Equipo'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AdminLeanStartupTab(firestore: firestore),
            AdminFinancesTab(firestore: firestore),
            AdminValidationsTab(firestore: firestore),
            AdminDisputesTab(firestore: firestore),
            AdminUsersTab(firestore: firestore),
            AdminTeamTab(firestore: firestore),
          ],
        ),
      ),
    );
  }
}

class AdminValidationsTab extends StatelessWidget {
  final FirebaseFirestore? firestore;
  const AdminValidationsTab({super.key, this.firestore});

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  Future<void> _updateStatus(String id, String status) async {
    final isApproved = status == 'approved';
    await _db.collection('caregivers').doc(id).update({
      'verificationStatus': status,
      'isVerified': isApproved,
      'verified': isApproved,
    });
  }

  Future<void> _launchURL(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('caregivers')
          .where('verificationStatus', whereIn: ['pending', 'manual_review'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No hay cuidadores pendientes.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final id = docs[index].id;
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text(data['name'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['title'] ?? ''),
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: _db
                          .collection('caregivers')
                          .doc(id)
                          .collection('private')
                          .doc('verification')
                          .get(),
                      builder: (context, privSnap) {
                        final priv = privSnap.data?.data() ?? {};
                        final dniUrl = (priv['dniUrl'] ?? data['dniUrl'] ?? '').toString();
                        final crimUrl = (priv['criminalRecordUrl'] ?? data['criminalRecordUrl'] ?? '').toString();
                        return Row(
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.badge),
                              label: const Text('DNI'),
                              onPressed: () => _launchURL(dniUrl),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.description),
                              label: const Text('PDF'),
                              onPressed: () => _launchURL(crimUrl),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _updateStatus(id, 'rejected')),
                    IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _updateStatus(id, 'approved')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class AdminDisputesTab extends StatefulWidget {
  final FirebaseFirestore? firestore;
  const AdminDisputesTab({super.key, this.firestore});

  @override
  State<AdminDisputesTab> createState() => _AdminDisputesTabState();
}

class _AdminDisputesTabState extends State<AdminDisputesTab> {
  bool _isLoading = false;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<void> _resolveDispute(BuildContext context, Map<String, dynamic> bookingData, String id, String resolutionType) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    // show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final totalPaid = (bookingData['totalPaid'] as num? ?? 0).toDouble();
      final cost = (bookingData['cost'] as num? ?? 0).toDouble();
      final trueCost = totalPaid > 0 ? totalPaid : cost;
      
      double refundToClient = 0;
      double payoutToCaregiver = 0;
      
      if (resolutionType == 'refunded') {
        refundToClient = trueCost;
      } else if (resolutionType == 'released') {
        payoutToCaregiver = (bookingData['caregiverPayout'] as num? ?? 0).toDouble();
        if (payoutToCaregiver == 0) {
          final commission = trueCost * (bookingData['caregiverCommissionRate'] as num? ?? 0.18).toDouble();
          payoutToCaregiver = trueCost - commission;
        }
      } else if (resolutionType == 'resolved_partial') {
        refundToClient = trueCost / 2;

        payoutToCaregiver = (bookingData['caregiverPayout'] as num? ?? 0).toDouble() / 2;
        if (payoutToCaregiver == 0) {
          final halfCost = trueCost / 2;
          final commission = halfCost * (bookingData['caregiverCommissionRate'] as num? ?? 0.18).toDouble();
          payoutToCaregiver = halfCost - commission;
        }
      }
      
      await FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('adminResolveDispute').call({
        'bookingId': id,
        'refundToClient': refundToClient,
        'payoutToCaregiver': payoutToCaregiver,
      });
      
      if (context.mounted) {
        CustomSnackBar.show(context, message: 'Disputa resuelta exitosamente', type: SnackBarType.success);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (context.mounted) {
        CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.error);
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('bookings').where('disputeEscalated', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs.where((d) => (d.data() as Map<String, dynamic>)['escrowStatus'] != 'resolved_partial').toList();
        if (docs.isEmpty) return const Center(child: Text('No hay disputas activas.'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final id = docs[index].id;
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                title: Text('Reserva: $id'),
                subtitle: Text('Motivo: ${data['disputeReason']}\nImporte Disputado: ${data['disputeAmount']}€'),
                trailing: PopupMenuButton<String>(
                  onSelected: (val) => _resolveDispute(context, data, id, val),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'refunded', child: Text('Devolver al cliente')),
                    const PopupMenuItem(value: 'released', child: Text('Pagar al cuidador')),
                    const PopupMenuItem(value: 'resolved_partial', child: Text('Acuerdo 50/50')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class AdminUsersTab extends StatefulWidget {
  final FirebaseFirestore? firestore;
  const AdminUsersTab({super.key, this.firestore});

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  String query = '';

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<void> _deleteUser(String id, String collection) async {
    final db = _db;
    final batch = db.batch();
    batch.delete(db.collection(collection).doc(id));
    if (collection != 'users') {
      batch.delete(db.collection('users').doc(id));
    } else {
      batch.delete(db.collection('caregivers').doc(id));
      batch.delete(db.collection('clients').doc(id));
    }
    await batch.commit();
  }

  Future<void> _blockUserDialog(String id) async {
    int days = 5;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloquear Cuidador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('5 Días'), onTap: () { days = 5; Navigator.pop(ctx, true); }),
            ListTile(title: const Text('Expulsar (10 Años)'), onTap: () { days = 3650; Navigator.pop(ctx, true); }),
            ListTile(title: const Text('Desbloquear'), onTap: () { days = 0; Navigator.pop(ctx, true); }),
          ],
        ),
      )
    ).then((val) async {
      if (val == true) {
        try {
          await FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('adminBlockCaregiver').call({
            'caregiverId': id,
            'days': days,
          });
          if (mounted) CustomSnackBar.show(context, message: 'Estado actualizado', type: SnackBarType.success);
        } catch(e) {
          if (mounted) CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.error);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(labelText: 'Buscar UID o Nombre', border: OutlineInputBorder()),
            onChanged: (val) => setState(() => query = val),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final docs = snapshot.data!.docs.where((d) {
                final email = (d.data() as Map<String, dynamic>)['email']?.toString().toLowerCase() ?? '';
                final role = (d.data() as Map<String, dynamic>)['role']?.toString().toLowerCase() ?? '';
                return email.contains(query.toLowerCase()) || role.contains(query.toLowerCase()) || d.id.contains(query);
              }).toList();

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final id = docs[index].id;
                  final role = data['role'] ?? 'unknown';
                  return ListTile(
                    title: Text(data['email'] ?? 'Sin email'),
                    subtitle: Text('Rol: $role | UID: $id\nEstado: ${data['status'] ?? 'active'}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (role == 'caregiver')
                          IconButton(
                            icon: const Icon(Icons.block, color: Colors.orange),
                            onPressed: () => _blockUserDialog(id),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteUser(id, 'users'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdminTeamTab extends StatefulWidget {
  final FirebaseFirestore? firestore;
  const AdminTeamTab({super.key, this.firestore});

  @override
  State<AdminTeamTab> createState() => _AdminTeamTabState();
}

class _AdminTeamTabState extends State<AdminTeamTab> {
  final TextEditingController _emailController = TextEditingController();

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addAdmin(String email) async {
    if (email.isEmpty) return;
    await _db.collection('admins').doc(email).set({
      'email': email,
      '2faEnabled': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _removeAdmin(String email) async {
    if (email == 'maverick6576@gmail.com') return; // Master admin check
    await _db.collection('admins').doc(email).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Nuevo Email Admin', border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.red, size: 36),
                onPressed: () {
                  _addAdmin(_emailController.text.trim());
                  _emailController.clear();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('admins').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final id = docs[index].id;
                  final data = docs[index].data() as Map<String, dynamic>;
                  final has2FA = data['2faEnabled'] == true;

                  return ListTile(
                    leading: Icon(has2FA ? Icons.security : Icons.warning, color: has2FA ? Colors.green : Colors.orange),
                    title: Text(id, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: id == 'maverick6576@gmail.com' 
                        ? const Text('ROOT')
                        : IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeAdmin(id),
                          ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class AdminFinancesTab extends StatefulWidget {
  final FirebaseFirestore? firestore;
  const AdminFinancesTab({super.key, this.firestore});

  @override
  State<AdminFinancesTab> createState() => _AdminFinancesTabState();
}

class _AdminFinancesTabState extends State<AdminFinancesTab> {
  String _statusFilter = 'Todos';
  String _escrowFilter = 'Todos';

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  DateTimeRange? _dateRange;

  void _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.red,
            colorScheme: const ColorScheme.light(primary: Colors.red),
            buttonTheme: const ButtonThemeData(textTheme: ButtonTextTheme.primary),
          ),
          child: child!,
        );
      },
    );
    if (range != null) {
      setState(() {
        _dateRange = range;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filters Header
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Colors.grey.shade200,
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _statusFilter,
                hint: const Text('Estado Reserva'),
                items: ['Todos', 'pending', 'confirmed', 'completed', 'cancelled', 'cancelledLate']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e == 'Todos' ? 'Estado: Todos' : e)))
                    .toList(),
                onChanged: (val) => setState(() => _statusFilter = val!),
              ),
              DropdownButton<String>(
                value: _escrowFilter,
                hint: const Text('Estado Escrow'),
                items: [
                  'Todos',
                  'held',
                  'released_manual',
                  'released_auto',
                  'released',
                  'refunded',
                  'resolved_partial',
                ]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e == 'Todos' ? 'Escrow: Todos' : e)))
                    .toList(),
                onChanged: (val) => setState(() => _escrowFilter = val!),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dateRange == null
                    ? 'Fechas: Todas'
                    : '${_dateRange!.start.day}/${_dateRange!.start.month} - ${_dateRange!.end.day}/${_dateRange!.end.month}'),
                onPressed: _pickDateRange,
              ),
              if (_dateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red),
                  onPressed: () => setState(() => _dateRange = null),
                )
            ],
          ),
        ),
        
        // Data List & KPIs
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('bookings').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Error al cargar datos.'));
              }
              
              final allDocs = snapshot.data!.docs;
              
              // Apply Filters
              final filteredDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] ?? '';
                final escrow = data['escrowStatus'] ?? '';
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
                
                if (_statusFilter != 'Todos' && status != _statusFilter) return false;
                if (_escrowFilter != 'Todos' && escrow != _escrowFilter) return false;
                if (_dateRange != null) {
                  if (createdAt.isBefore(_dateRange!.start) || createdAt.isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
                    return false;
                  }
                }
                return true;
              }).toList();
              
              // Calculate KPIs
              double totalVol = 0;
              double totalGrossProfit = 0;
              double totalStripeFees = 0;
              double totalCaregiverPayouts = 0;
              
              for (var doc in filteredDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] ?? 'unknown';
                final escrow = data['escrowStatus'] ?? 'unknown';
                final cost = (data['cost'] as num?)?.toDouble() ?? 0;
                final clientFee = (data['clientFee'] as num?)?.toDouble() ?? 0;
                final totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? (cost + clientFee);
                final cgCommRate = (data['caregiverCommissionRate'] as num?)?.toDouble() ?? 0.18;
                
                // Stripe fee (1.5% + 0.25) applies to the total amount charged to the client originally
                final stripeFee = totalPaid > 0 ? (totalPaid * 0.015) + 0.25 : 0.0;
                totalStripeFees += stripeFee;
                totalVol += totalPaid;
                
                double caregiverPayout = 0;
                double senicareProfit = 0;
                
                if (status == 'cancelled' && escrow == 'refunded') {
                    double managementFee = max(1.0, cost * 0.05);
                    senicareProfit = managementFee;
                } else if (status == 'cancelledLate' && (escrow == 'resolved_partial' || escrow == 'held')) {
                    caregiverPayout = cost * 0.45;
                    senicareProfit = totalPaid - (cost * 0.45) - (cost * 0.45);
                } else if (status != 'cancelledLate' && escrow == 'resolved_partial') {
                    double expectedPayout = (data['caregiverPayout'] as num?)?.toDouble() ?? (cost - (cost * cgCommRate));
                    caregiverPayout = expectedPayout / 2;
                    double expectedSenicare = totalPaid - expectedPayout;
                    senicareProfit = expectedSenicare / 2;
                } else if (escrow == 'released' || escrow == 'released_manual' || escrow == 'released_auto') {
                    caregiverPayout = (data['caregiverPayout'] as num?)?.toDouble() ?? (cost - (cost * cgCommRate));
                    senicareProfit = totalPaid - caregiverPayout;
                }
                
                totalGrossProfit += senicareProfit;
                totalCaregiverPayouts += caregiverPayout;
              }
              
              final totalNetProfit = totalGrossProfit - totalStripeFees;

              return Column(
                children: [
                  // KPI Bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildKpiCard('Volumen', totalVol, Colors.blue),
                        _buildKpiCard('Beneficio Neto', totalNetProfit, Colors.green),
                        _buildKpiCard('Pagos Cuidadores', totalCaregiverPayouts, Colors.orange),
                        _buildKpiCard('Costes Stripe', totalStripeFees, Colors.red),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Detailed List
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final data = filteredDocs[index].data() as Map<String, dynamic>;
                        final id = filteredDocs[index].id;
                        
                        final status = data['status'] ?? 'unknown';
                        final escrow = data['escrowStatus'] ?? 'unknown';
                        final cost = (data['cost'] as num?)?.toDouble() ?? 0;
                        final clientFee = (data['clientFee'] as num?)?.toDouble() ?? 0;
                        final totalPaid = (data['totalPaid'] as num?)?.toDouble() ?? (cost + clientFee);
                        final cgCommRate = (data['caregiverCommissionRate'] as num?)?.toDouble() ?? 0.18;
                        final stripeFee = totalPaid > 0 ? (totalPaid * 0.015) + 0.25 : 0.0;
                        
                        double refundToClient = 0;
                        double caregiverPayout = 0;
                        double senicareProfit = 0;
                        String scenarioName = 'Pendiente / Retenido';
                        
                        if (status == 'cancelled' && escrow == 'refunded') {
                            scenarioName = 'Cancelación Temprana';
                            double managementFee = max(1.0, cost * 0.05);
                            refundToClient = max(0.0, totalPaid - managementFee);
                            senicareProfit = managementFee;
                        } else if (status == 'cancelledLate' && (escrow == 'resolved_partial' || escrow == 'held')) {
                            scenarioName = 'Cancelación Tardía (45/45)';
                            refundToClient = cost * 0.45;
                            caregiverPayout = cost * 0.45;
                            senicareProfit = totalPaid - refundToClient - caregiverPayout;
                        } else if (status != 'cancelledLate' && escrow == 'resolved_partial') {
                            scenarioName = 'Disputa 50/50';
                            refundToClient = totalPaid / 2;
                            double expectedPayout = (data['caregiverPayout'] as num?)?.toDouble() ?? (cost - (cost * cgCommRate));
                            caregiverPayout = expectedPayout / 2;
                            senicareProfit = totalPaid - refundToClient - caregiverPayout;
                        } else if (escrow == 'released' || escrow == 'released_manual' || escrow == 'released_auto') {
                            scenarioName = escrow == 'released_auto' ? 'Completado (Auto)' : 'Completado (100%)';
                            caregiverPayout = (data['caregiverPayout'] as num?)?.toDouble() ?? (cost - (cost * cgCommRate));
                            senicareProfit = totalPaid - caregiverPayout;
                        } else {
                            // Proyectado
                            caregiverPayout = (data['caregiverPayout'] as num?)?.toDouble() ?? (cost - (cost * cgCommRate));
                            senicareProfit = totalPaid - caregiverPayout;
                        }
                        
                        final net = senicareProfit - stripeFee;
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ExpansionTile(
                            leading: Icon(
                              status == 'completed' ? Icons.check_circle : (status == 'cancelled' || status == 'cancelledLate' ? Icons.cancel : Icons.schedule),
                              color: status == 'completed' ? Colors.green : (status == 'cancelled' || status == 'cancelledLate' ? Colors.red : Colors.orange),
                            ),
                            title: Text('Reserva: $id', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('Estado: $status | Escrow: $escrow\nEscenario: $scenarioName'),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                color: Colors.grey.shade50,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Cuidador: ${data['caregiverName'] ?? data['caregiverId']}'),
                                        Text('Cliente: ${data['clientId'].toString().substring(0, min(8, data['clientId'].toString().length))}'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('Desglose Financiero:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    _buildFinanceRow('Coste Base Servicio:', cost),
                                    _buildFinanceRow('+ Fee Cliente:', clientFee),
                                    const Divider(),
                                    _buildFinanceRow('Total Original (Cliente):', totalPaid, isBold: true),
                                    const SizedBox(height: 8),
                                    if (refundToClient > 0)
                                      _buildFinanceRow('Devolución al Cliente:', refundToClient, color: Colors.red),
                                    if (caregiverPayout > 0)
                                      _buildFinanceRow('Pago Neto al Cuidador:', caregiverPayout, color: Colors.orange),
                                    const SizedBox(height: 8),
                                    _buildFinanceRow(escrow == 'held' ? 'Beneficio SeniCare (Proyectado):' : 'Beneficio Bruto SeniCare:', senicareProfit),
                                    _buildFinanceRow('- Costes Stripe (1.5% + 0.25):', -stripeFee, color: Colors.red),
                                    const Divider(),
                                    _buildFinanceRow('Beneficio Neto SeniCare:', net, isBold: true, color: Colors.green),
                                  ],
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String title, double value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text('${value.toStringAsFixed(2)} €', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildFinanceRow(String label, double value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text('${value.toStringAsFixed(2)} €', style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          )),
        ],
      ),
    );
  }
}
