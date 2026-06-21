import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'report_detail_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            "Dashboard",
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: "Logout",
              onPressed: () async {
                await _authService.signOut();
              },
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.campaign), text: "Laporan SOS"),
              Tab(icon: Icon(Icons.people), text: "Kelola Pengguna"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SOSReportsTab(),
            ManageUsersTab(),
          ],
        ),
      ),
    );
  }
}

class SOSReportsTab extends StatefulWidget {
  const SOSReportsTab({super.key});

  @override
  State<SOSReportsTab> createState() => _SOSReportsTabState();
}

class _SOSReportsTabState extends State<SOSReportsTab> {
  final _firestoreService = FirestoreService();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _reportsStream;

  @override
  void initState() {
    super.initState();
    _reportsStream = _firestoreService.getSOSReportsStream();
  }

  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return "-";
    final dt = timestamp.toDate();
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    return "$day/$month/$year $hour:$minute";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reportsStream,
      builder: (reportsContext, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.red),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                "Terjadi kesalahan saat memuat data: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  "Tidak ada laporan SOS saat ini",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: docs.length,
          itemBuilder: (itemContext, index) {
            final doc = docs[index];
            final data = doc.data();
            final String reportId = doc.id;
            final String name = data['nama'] ?? 'Tanpa Nama';
            final String status = data['status'] ?? 'pending';
            final Timestamp? createdAt = data['createdAt'] as Timestamp?;

            Color statusColor = Colors.red;
            Color cardBorderColor = Colors.red.shade200;
            Color avatarBg = Colors.red.shade50;
            IconData statusIcon = Icons.campaign;

            if (status == 'accepted') {
              statusColor = Colors.green.shade700;
              cardBorderColor = Colors.green.shade200;
              avatarBg = Colors.green.shade50;
              statusIcon = Icons.check_circle;
            } else if (status == 'cancelled') {
              statusColor = Colors.grey.shade600;
              cardBorderColor = Colors.grey.shade300;
              avatarBg = Colors.grey.shade100;
              statusIcon = Icons.cancel;
            }

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: cardBorderColor,
                  width: 1,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: avatarBg,
                  radius: 24,
                  child: Icon(
                    statusIcon,
                    color: statusColor,
                    size: 24,
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateTime(createdAt),
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status == 'accepted'
                        ? 'diterima'
                        : status == 'cancelled'
                            ? 'dibatalkan'
                            : status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (routeContext) => ReportDetailPage(
                        reportId: reportId,
                        reportData: data,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class ManageUsersTab extends StatefulWidget {
  const ManageUsersTab({super.key});

  @override
  State<ManageUsersTab> createState() => _ManageUsersTabState();
}

class _ManageUsersTabState extends State<ManageUsersTab> {
  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();
  String _searchQuery = "";
  late Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;

  @override
  void initState() {
    super.initState();
    _usersStream = _firestoreService.getAllUsersStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleUserActiveStatus(String uid, String name, bool value) async {
    try {
      await _firestoreService.updateUserActiveStatus(uid, value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? "Akun $name berhasil diaktifkan"
                  : "Akun $name berhasil dinonaktifkan",
            ),
            backgroundColor: value ? Colors.green : Colors.red.shade700,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal mengubah status: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val.toLowerCase().trim();
              });
            },
            decoration: InputDecoration(
              hintText: "Cari pengguna berdasarkan nama/email...",
              prefixIcon: const Icon(Icons.search, color: Colors.red),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = "";
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              ),
            ),
          ),
        ),
        
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _usersStream,
            builder: (usersContext, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.red));
              }

              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
              }

              final docs = snapshot.data?.docs ?? [];
              final filteredDocs = docs.where((doc) {
                final data = doc.data();
                final name = (data['nama'] ?? '').toString().toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();
                final phone = (data['noHp'] ?? '').toString();
                return name.contains(_searchQuery) || email.contains(_searchQuery) || phone.contains(_searchQuery);
              }).toList();

              if (filteredDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        "Pengguna tidak ditemukan",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: filteredDocs.length,
                itemBuilder: (itemContext, index) {
                  final doc = filteredDocs[index];
                  final data = doc.data();
                  final String uid = doc.id;
                  final String name = data['nama'] ?? 'Tanpa Nama';
                  final String email = data['email'] ?? '-';
                  final String phone = data['noHp'] ?? '-';
                  final String role = data['role'] ?? 'user';
                  final bool isActive = data['isActive'] ?? true;

                  final bool isAdmin = role == 'admin';

                  return Card(
                    elevation: 1.5,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isActive ? Colors.grey.shade200 : Colors.red.shade100,
                        width: 1,
                      ),
                    ),
                    color: isActive ? Colors.white : Colors.red.shade50.withOpacity(0.15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: isAdmin
                                ? Colors.blue.shade100
                                : isActive
                                    ? Colors.green.shade100
                                    : Colors.red.shade100,
                            child: Icon(
                              isAdmin ? Icons.admin_panel_settings : Icons.person,
                              color: isAdmin
                                  ? Colors.blue.shade700
                                  : isActive
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isAdmin
                                            ? Colors.blue.shade50
                                            : isActive
                                                ? Colors.green.shade50
                                                : Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isAdmin
                                            ? "ADMIN"
                                            : isActive
                                                ? "AKTIF"
                                                : "NONAKTIF",
                                        style: TextStyle(
                                          color: isAdmin
                                              ? Colors.blue.shade700
                                              : isActive
                                                  ? Colors.green.shade700
                                                  : Colors.red.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(email, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text("No. HP: $phone", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isAdmin)
                            Switch(
                              value: isActive,
                              activeColor: Colors.green,
                              activeTrackColor: Colors.green.shade100,
                              inactiveThumbColor: Colors.red,
                              inactiveTrackColor: Colors.red.shade100,
                              onChanged: (value) => _toggleUserActiveStatus(uid, name, value),
                            ),
                        ],
                      ),
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
