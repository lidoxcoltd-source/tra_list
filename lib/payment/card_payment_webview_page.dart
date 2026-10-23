import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'card_payment_service.dart';

enum CardWebViewResult { success, cancelled, aborted }

class CardPaymentWebViewPage extends StatefulWidget {
  const CardPaymentWebViewPage({super.key, required this.url});
  final String url;

  @override
  State<CardPaymentWebViewPage> createState() => _CardPaymentWebViewPageState();
}

class _CardPaymentWebViewPageState extends State<CardPaymentWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(CardPaymentService.returnPrefix)) {
              final result = Uri.tryParse(
                request.url,
              )?.queryParameters['result'];
              _close(
                result == 'success'
                    ? CardWebViewResult.success
                    : CardWebViewResult.cancelled,
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                setState(() {
                  _error = true;
                  _loading = false;
                });
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _close(CardWebViewResult result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _confirmExit() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unataka kusitisha malipo?'),
        content: const Text('Tutakagua kama malipo yako yamekamilika au la.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Endelea kulipa'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sitisha'),
          ),
        ],
      ),
    );
    if (stop == true) _close(CardWebViewResult.aborted);
  }

  void _retry() {
    setState(() {
      _error = false;
      _loading = true;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lipa kwa Kadi'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _confirmExit,
          ),
        ),
        body: Stack(
          children: [
            if (!_error) WebViewWidget(controller: _controller),
            if (_loading && !_error)
              const Center(child: CircularProgressIndicator()),
            if (_error)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Ukurasa wa malipo haukufunguka. Angalia intaneti yako kisha ujaribu tena.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Jaribu tena'),
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
}
