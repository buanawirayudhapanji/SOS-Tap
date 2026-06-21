import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'firestore_service.dart';

class ReportDetailPage extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> reportData;

  const ReportDetailPage({
    super.key,
    required this.reportId,
    required this.reportData,
  });

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  final _firestoreService = FirestoreService();
  bool _isAccepting = false;

  Future<void> _acceptReport() async {
    setState(() {
      _isAccepting = true;
    });

    try {
      await _firestoreService.updateReportStatus(widget.reportId, 'accepted');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Laporan berhasil diterima (ACCEPTED)"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal memproses laporan: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_reports')
          .doc(widget.reportId)
          .snapshots(),
      builder: (context, snapshot) {
        // Fallback to widget data if stream is waiting or fails
        final data = snapshot.hasData && snapshot.data!.exists
            ? snapshot.data!.data()!
            : widget.reportData;

        final String name = data['nama'] ?? 'Tanpa Nama';
        final String userId = data['userId'] ?? '';
        final double latitude = (data['latitude'] as num?)?.toDouble() ?? 0.0;
        final double longitude = (data['longitude'] as num?)?.toDouble() ?? 0.0;
        final String status = data['status'] ?? 'pending';

        final bool isPending = status == 'pending';
        final bool isCancelled = status == 'cancelled';
        final LatLng reporterLocation = LatLng(latitude, longitude);

        return Scaffold(
          appBar: AppBar(
            title: const Text("Detail Laporan SOS"),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // OpenStreetMap View (Free & Key-less alternative)
                SizedBox(
                  height: 300,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: reporterLocation,
                      initialZoom: 16.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sos_tap',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: reporterLocation,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "STATUS LAPORAN",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isPending ? Colors.red : Colors.green,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),

                      // Reporter Name
                      _buildInfoRow(
                        icon: Icons.person,
                        label: "Nama Pelapor",
                        value: name,
                      ),
                      const SizedBox(height: 20),

                      // Reporter Phone Number (Fetched from user document)
                      FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        future: _firestoreService.getUser(userId),
                        builder: (context, userSnapshot) {
                          String phone = "Memuat...";
                          if (userSnapshot.connectionState == ConnectionState.done) {
                            if (userSnapshot.hasData && userSnapshot.data!.exists) {
                              phone = userSnapshot.data!.data()?['noHp'] ?? '-';
                            } else {
                              phone = "Tidak ditemukan";
                            }
                          }
                          return _buildInfoRow(
                            icon: Icons.phone,
                            label: "Nomor HP Pelapor",
                            value: phone,
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Location Coordinates
                      _buildInfoRow(
                        icon: Icons.location_on,
                        label: "Koordinat",
                        value: "Lat: $latitude\nLng: $longitude",
                      ),
                      const SizedBox(height: 40),

                      // Action Button
                      if (isPending)
                        ElevatedButton(
                          onPressed: _isAccepting ? null : _acceptReport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isAccepting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text(
                                      "TERIMA LAPORAN (ACCEPT)",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                        )
                      else if (isCancelled)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cancel, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Text(
                                "Laporan dibatalkan oleh pelapor",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                "Laporan ini telah ditangani",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.red, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
