import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/finance_store.dart';
import '../l10n/app_language.dart';
import '../services/invoice_service.dart';
import '../config/flask_config.dart';
import '../services/recommendation_service.dart';
import 'recommendation_review.dart';
import '../widgets/design.dart';
import 'invoice_review.dart';
import 'transactions.dart';

class ScanPage extends StatefulWidget {
  final FinanceStore store;
  final bool productMode, shoppingListMode;
  const ScanPage({
    super.key,
    required this.store,
    this.productMode = false,
    this.shoppingListMode = false,
  });
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  Uint8List? photo;
  String filename = 'invoice.jpg';
  String? error;
  bool busy = false;
  bool processing = false;
  bool userSelectedPhoto = false;
  InvoiceService? service;
  RecommendationService? productService;
  late String baseUrl;
  bool get cameraSupported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    baseUrl = flaskApiUrl();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      recoverImage();
    }
  }

  Future<void> recoverImage() async {
    try {
      final recovered = await ImagePicker().retrieveLostData();
      if (!mounted || recovered.isEmpty || userSelectedPhoto || busy) return;
      if (recovered.files?.isNotEmpty ?? false) {
        await selectFile(recovered.files!.first);
      } else if (recovered.exception != null) {
        setState(
          () =>
              error =
                  'Could not open the camera or photo library. Check permissions.',
        );
      }
    } catch (_) {
      // A new capture remains available if Android has no recoverable image.
    }
  }

  Future<void> selectFile(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > invoiceMaxImageBytes) {
      throw const InvoiceApiException('image_too_large');
    }
    if (mounted) {
      setState(() {
        photo = bytes;
        filename = file.name;
        error = null;
      });
    }
  }

  Future<void> capture(ImageSource source) async {
    if (busy) return;
    userSelectedPhoto = true;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 75,
      );
      if (picked != null) await selectFile(picked);
    } on InvoiceApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on PlatformException {
      if (mounted) {
        setState(
          () =>
              error =
                  'Could not open the camera or photo library. Check permissions.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not read the selected image. Try another photo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> analyze() async {
    if (busy || photo == null) return;
    final analyzedPhoto = photo!;
    final analyzedFilename = filename;
    userSelectedPhoto = true;
    setState(() {
      busy = true;
      processing = true;
      error = null;
    });
    service = InvoiceService(baseUrl: baseUrl);
    try {
      if (widget.productMode || widget.shoppingListMode) {
        productService = RecommendationService(baseUrl: baseUrl);
        final result =
            widget.shoppingListMode
                ? await productService!.readShoppingImage(
                  analyzedPhoto,
                  analyzedFilename,
                )
                : await productService!.identify(
                  analyzedPhoto,
                  analyzedFilename,
                );
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder:
                (_) => RecommendationReviewPage(
                  store: widget.store,
                  review: result,
                  photo: analyzedPhoto,
                ),
          ),
        );
        return;
      }
      final result = await service!.analyze(analyzedPhoto, analyzedFilename);
      if (!mounted) return;
      final review = await Navigator.push<InvoiceReviewResult>(
        context,
        MaterialPageRoute(
          builder:
              (_) => InvoiceReviewScreen(
                store: widget.store,
                invoice: result.invoice,
                receipt: base64Encode(analyzedPhoto),
                warnings: result.warnings,
              ),
        ),
      );
      if (!mounted) return;
      if (review?.action == InvoiceReviewAction.saved &&
          review?.entry != null) {
        Navigator.pop(context, review!.entry);
      } else if (review?.action == InvoiceReviewAction.retake) {
        setState(() => photo = null);
        // Clear the lock before opening the camera again.
        setState(() => busy = false);
        await capture(
          cameraSupported ? ImageSource.camera : ImageSource.gallery,
        );
      } else if (review?.action == InvoiceReviewAction.analyzeAgain) {
        setState(() => busy = false);
        await analyze();
      }
    } on RecommendationApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on InvoiceApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'AI analysis failed. Please try again.');
      }
    } finally {
      productService?.close();
      productService = null;
      service?.close();
      service = null;
      if (mounted) {
        setState(() {
          busy = false;
          processing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    productService?.close();
    service?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        PageHeading(
          'Capture. Review. Done.',
          widget.shoppingListMode
              ? 'Import list or invoice'
              : widget.productMode
              ? 'Scan Product'
              : 'Scan Invoice',
        ),
        AppText(
          widget.shoppingListMode
              ? 'Capture the full shopping list or invoice with clear item names and quantities.'
              : widget.productMode
              ? 'Capture the product label, brand, model and package size clearly.'
              : 'Capture the whole receipt with clear text and all totals visible.',
        ),
        const SizedBox(height: 20),
        Surface(
          color: ink,
          child:
              photo == null
                  ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          size: 64,
                          color: blue,
                        ),
                        SizedBox(height: 18),
                        AppText(
                          widget.shoppingListMode
                              ? 'Turn a list into shopping options'
                              : widget.productMode
                              ? 'Find the product. Compare the price.'
                              : 'Your invoice, organized',
                        ),
                        SizedBox(height: 8),
                        AppText(
                          'Preview your photo before sending it to the analysis server.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                  : Column(
                    children: [
                      const AppText('Photo preview'),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          photo!,
                          height: 300,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (_, __, ___) =>
                                  const AppText('Receipt preview unavailable'),
                        ),
                      ),
                    ],
                  ),
        ),
        const SizedBox(height: 20),
        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          AppText(
            processing
                ? (widget.shoppingListMode
                    ? 'Reading your list…'
                    : widget.productMode
                    ? 'Identifying product…'
                    : 'Analyzing invoice…')
                : 'Opening photo picker…',
          ),
          if (processing)
            const AppText(
              'The analysis model may take a few minutes. Keep this screen open.',
            ),
          const SizedBox(height: 20),
        ],
        if (error != null) ...[
          Surface(
            child: AppText(
              error!,
              style: const TextStyle(color: Color(0xFFFFB4AB)),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (photo != null) ...[
          FilledButton.icon(
            key: const Key('analyze-invoice'),
            onPressed: busy ? null : analyze,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: AppText(
              widget.shoppingListMode
                  ? 'Read list or invoice'
                  : widget.productMode
                  ? 'Identify Product'
                  : 'Analyze Invoice',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (cameraSupported)
          FilledButton.icon(
            onPressed: busy ? null : () => capture(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: AppText(photo == null ? 'Take a photo' : 'Retake Photo'),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : () => capture(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: AppText(
            widget.shoppingListMode
                ? 'Choose list or invoice image'
                : widget.productMode
                ? 'Choose product image'
                : 'Choose receipt image',
          ),
        ),
        if (!widget.productMode && !widget.shoppingListMode)
          TextButton(
            onPressed: busy ? null : () => editEntry(context, widget.store),
            child: const AppText('Enter expense manually'),
          ),
        const SizedBox(height: 12),
        const AppText(
          'Your photo is sent to the analysis server. You review every field before anything is saved.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ),
  );
}
