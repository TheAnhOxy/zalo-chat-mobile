import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants/app_colors.dart';
import '../../navigation/app_router.dart';
import '../../services/contacts_api_service.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _handling = false;

  String? _extractPhoneFromQr(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme == 'quickchat' && uri.host == 'add-friend') {
        final phone = uri.queryParameters['phone'];
        if (phone != null && phone.trim().isNotEmpty) return phone.trim();
      }
      // fallback: plain text phone
      final cleaned = raw.trim();
      if (RegExp(r'^\+?\d{7,15}$').hasMatch(cleaned)) return cleaned;
    } catch (_) {}
    return null;
  }

  Future<void> _handleCode(String raw) async {
    if (_handling) return;
    _handling = true;
    try {
      final phone = _extractPhoneFromQr(raw);
      if (phone == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR không hợp lệ'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _handling = false;
        return;
      }

      final res = await ContactsApiService.instance.searchByPhone(phone);
      if (!mounted) return;
      if (!res.isSuccess || res.data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.error ?? 'Không tìm thấy người dùng'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _handling = false;
        return;
      }

      // Dừng camera trước khi chuyển màn.
      await _controller.stop();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRouter.foundUser,
        arguments: res.data!,
      );
    } catch (e) {
      log('❌ QR scan handle error: $e');
      _handling = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Quét mã QR',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_rounded),
          ),
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final raw = barcodes.first.rawValue;
              if (raw == null || raw.isEmpty) return;
              _handleCode(raw);
            },
          ),
          // Overlay khung quét
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScannerOverlayPainter(),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Đưa mã QR vào trong khung để quét',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Inter',
                  fontSize: 13,
                ),
              ),
            ),
          ),
          if (_handling)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);
    canvas.drawRect(Offset.zero & size, overlayPaint);

    final scanSize = size.shortestSide * 0.62;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2;
    final rect = Rect.fromLTWH(left, top, scanSize, scanSize);

    // Clear center
    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      clearPaint,
    );

    final border = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

