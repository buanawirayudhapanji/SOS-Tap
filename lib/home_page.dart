import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'location_service.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _locationService = LocationService();
  bool _isSendingSOS = false;
  Timer? _cancelTimer;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _reportsStream;

  @override
  void initState() {
    super.initState();
    final user = _authService.currentUser;
    if (user != null) {
      _userStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots();
      _reportsStream = FirebaseFirestore.instance
          .collection('sos_reports')
          .where('userId', isEqualTo: user.uid)
          .snapshots();
    }
    // Start periodic timer to check cancel timeout countdown in UI
    _cancelTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _cancelTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendSOS(String userName) async {
    setState(() {
      _isSendingSOS = true;
    });

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception("User tidak ditemukan");

      // 1. Get GPS coordinates
      final position = await _locationService.getCurrentLocation();

      // 2. Save report to Firestore
      await _firestoreService.createSOSReport(
        userId: user.uid,
        nama: userName,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Laporan SOS berhasil dikirim"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal mengirim SOS: ${e.toString().replaceAll("Exception: ", "")}"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSOS = false;
        });
      }
    }
  }

  Future<void> _confirmCancel(String reportId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Batalkan Laporan?"),
        content: const Text("Apakah Anda yakin ingin membatalkan laporan SOS ini?"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Kembali", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              "Ya, Batalkan",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestoreService.cancelReport(reportId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Laporan berhasil dibatalkan"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Gagal membatalkan laporan: $e"),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return "Baru saja";
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
    final user = _authService.currentUser;

    if (user == null || _userStream == null || _reportsStream == null) {
      return const Scaffold(
        body: Center(
          child: Text("Sesi telah berakhir"),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (profileContext, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.red),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Data pengguna tidak ditemukan di Firestore."),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _authService.signOut(),
                    child: const Text("Logout"),
                  )
                ],
              ),
            ),
          );
        }

        final userData = snapshot.data!.data()!;
        final String name = userData['nama'] ?? 'Pengguna';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _reportsStream,
          builder: (reportsContext, reportsSnapshot) {
            if (reportsSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Colors.red),
                ),
              );
            }

            final reports = reportsSnapshot.data?.docs ?? [];
            // Sort client-side to avoid composite index crash
            reports.sort((a, b) {
              final aTime = a.data()['createdAt'] as Timestamp?;
              final bTime = b.data()['createdAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return -1;
              if (bTime == null) return 1;
              return bTime.compareTo(aTime);
            });

            // Anti-Spam Validation: check if latest report is still pending
            final latestReport = reports.isNotEmpty ? reports.first : null;
            final String latestStatus = latestReport != null ? (latestReport.data()['status'] ?? 'pending') : '';
            final bool hasPendingReport = latestStatus == 'pending';

            // Cancel check: within 1 minute (60 seconds)
            bool canCancel = false;
            int secondsLeft = 0;
            if (hasPendingReport && latestReport != null) {
              final Timestamp? createdAt = latestReport.data()['createdAt'] as Timestamp?;
              if (createdAt != null) {
                final diff = DateTime.now().difference(createdAt.toDate());
                secondsLeft = 60 - diff.inSeconds;
                canCancel = secondsLeft > 0;
              } else {
                // If timestamp is newly created and not yet synced with server, allow cancel
                canCancel = true;
                secondsLeft = 60;
              }
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  "SOS Tap",
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.person_outline),
                    tooltip: "Profil",
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (profileNavContext) => const ProfilePage(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: "Logout",
                    onPressed: () async {
                      await _authService.signOut();
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Welcome & Alert Status Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: hasPendingReport
                                ? [Colors.orange.shade700, Colors.amber.shade600]
                                : [Colors.red.shade800, Colors.red.shade600],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (hasPendingReport ? Colors.orange : Colors.red)
                                  .withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    "Halo, $name",
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    "USER",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasPendingReport
                                  ? "Laporan Anda sedang diproses oleh pemadam kebakaran. Tombol SOS dikunci sementara demi menghindari spam."
                                  : "Dalam situasi darurat kebakaran, tekan tombol merah di bawah untuk mengirimkan lokasi GPS Anda ke Pemadam Kebakaran secara instan.",
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.4,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Massive SOS Button in the Center
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: (_isSendingSOS || hasPendingReport)
                                  ? null
                                  : () => _sendSOS(name),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: hasPendingReport
                                      ? Colors.grey.shade400
                                      : _isSendingSOS
                                          ? Colors.red.shade900
                                          : Colors.red.shade600,
                                  boxShadow: _isSendingSOS
                                      ? [
                                          BoxShadow(
                                            color: Colors.red.withOpacity(0.4),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          )
                                        ]
                                      : hasPendingReport
                                          ? [
                                              BoxShadow(
                                                color: Colors.grey.withOpacity(0.2),
                                                blurRadius: 10,
                                                spreadRadius: 2,
                                              )
                                            ]
                                          : [
                                              BoxShadow(
                                                color: Colors.red.withOpacity(0.4),
                                                blurRadius: 20,
                                                spreadRadius: 8,
                                              ),
                                              BoxShadow(
                                                color: Colors.red.withOpacity(0.2),
                                                blurRadius: 40,
                                                spreadRadius: 16,
                                              ),
                                            ],
                                  border: Border.all(
                                    color: hasPendingReport
                                        ? Colors.grey.shade300
                                        : Colors.red.shade800,
                                    width: 8,
                                  ),
                                ),
                                child: Center(
                                  child: _isSendingSOS
                                      ? const Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 4,
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              "MENGIRIM...",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                          ],
                                        )
                                      : hasPendingReport
                                          ? const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.hourglass_disabled,
                                                  size: 48,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(height: 6),
                                                Text(
                                                  "PENDING",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 1.5,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  size: 48,
                                                  color: Colors.white,
                                                ),
                                                SizedBox(height: 6),
                                                Text(
                                                  "SOS",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 36,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                ),
                              ),
                            ),
                            if (hasPendingReport) ...[
                              const SizedBox(height: 12),
                              Text(
                                "Tombol dikunci. Laporan aktif sedang berjalan.",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Riwayat Laporan Section
                      Text(
                        "Riwayat Laporan Saya",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 12),

                      reports.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 36.0),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.history,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Belum ada riwayat laporan SOS",
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: reports.length,
                              itemBuilder: (itemContext, index) {
                                final report = reports[index];
                                final rData = report.data();
                                final String reportId = report.id;
                                final String status = rData['status'] ?? 'pending';
                                final Timestamp? createdAt = rData['createdAt'] as Timestamp?;
                                final double lat = (rData['latitude'] as num?)?.toDouble() ?? 0.0;
                                final double lng = (rData['longitude'] as num?)?.toDouble() ?? 0.0;

                                final bool isCurrentPending = reportId == latestReport?.id && status == 'pending';

                                Color statusColor = Colors.red;
                                if (status == 'accepted') {
                                  statusColor = Colors.green.shade700;
                                } else if (status == 'cancelled') {
                                  statusColor = Colors.grey.shade600;
                                }

                                return Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.campaign,
                                                  color: status == 'pending'
                                                      ? Colors.red
                                                      : status == 'accepted'
                                                          ? Colors.green
                                                          : Colors.grey,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _formatDateTime(createdAt),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: statusColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                status.toUpperCase(),
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "Lokasi: Lat $lat, Lng $lng",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        if (isCurrentPending && canCancel) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: () =>
                                                    _confirmCancel(reportId),
                                                icon: const Icon(Icons.cancel, size: 14),
                                                label: Text(
                                                  "Batalkan Laporan ($secondsLeft s)",
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red.shade50,
                                                  foregroundColor: Colors.red.shade700,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 12, vertical: 6),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(8),
                                                    side: BorderSide(
                                                        color: Colors.red.shade200),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
