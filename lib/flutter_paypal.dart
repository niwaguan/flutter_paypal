library flutter_paypal;

import 'dart:async';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:paypal_sdk/core.dart';
import 'package:paypal_sdk/orders.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'src/errors/network_error.dart';

class UsePaypal extends StatefulWidget {
  final Function onSuccess, onCancel, onError;
  final String returnURL, cancelURL, note;

  /// An array of purchase units. Each purchase unit establishes a contract
  /// between a payer and the payee. Each purchase unit represents either a full
  /// or partial order that the payer intends to purchase from the payee.
  final List<PurchaseUnitRequest> purchaseUnits;

  final PayPalEnvironment environment;

  const UsePaypal({
    Key? key,
    required this.onSuccess,
    required this.onError,
    required this.onCancel,
    required this.returnURL,
    required this.cancelURL,
    required this.purchaseUnits,
    required this.environment,
    this.note = '',
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return UsePaypalState();
  }
}

class UsePaypalState extends State<UsePaypal> {
  final Completer<WebViewController> _controller = Completer();
  String checkoutUrl = '';
  String navUrl = '';
  String executeUrl = '';
  bool loading = true;
  bool pageLoading = true;
  bool loadingError = false;
  int pressed = 0;

  late final paypalHttpClient = PayPalHttpClient(
    widget.environment,
    accessToken: null,
    loggingEnabled: true,
    accessTokenUpdatedCallback: (accessToken) async {
      // Persist token for re-use
    },
  );

  late final ordersApi = OrdersApi(paypalHttpClient);

  Order? order;

  Future<Order> createOrder() async {
    final order = await ordersApi.createOrder(
      OrderRequest(
        intent: OrderRequestIntent.capture,
        purchaseUnits: widget.purchaseUnits,
        applicationContext: ApplicationContext(
          returnUrl: widget.returnURL,
          cancelUrl: widget.cancelURL,
        ),
      ),
    );
    this.order = order;
    debugPrint("${order.toJson()}");
    return order;
  }

  loadPayment() async {
    setState(() {
      loading = true;
    });
    try {
      final order = await createOrder();
      final links = order.links;
      if (links != null) {
        setState(() {
          checkoutUrl =
              links.firstWhere((element) => element.rel == "approve").href;
          navUrl = checkoutUrl;
          executeUrl = checkoutUrl;
          // executeUrl =
          //     links.firstWhere((element) => element.rel == "execute").href;
          loading = false;
          pageLoading = false;
          loadingError = false;
        });
        (await _controller.future).loadUrl(checkoutUrl);
      } else {
        widget.onError({"msg": "unable to resolve order checkout url."});
        setState(() {
          loading = false;
          pageLoading = false;
          loadingError = true;
        });
      }
    } catch (e) {
      widget.onError(e);
      setState(() {
        loading = false;
        pageLoading = false;
        loadingError = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    loadPayment();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        actions: [
          if (pageLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: SpinKitFadingCube(
                color: Color(0xFFFF6B10),
                size: 10.0,
              ),
            )
        ],
        title: const Text("PayPal"),
        elevation: 0,
      ),
      body: SizedBox(
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: loading
            ? const Center(
                child: SpinKitFadingCube(
                  color: Color(0xFFFF6B10),
                  size: 30.0,
                ),
              )
            : loadingError
                ? Center(
                    child: NetworkError(
                      loadData: loadPayment,
                      message: "Something went wrong,",
                    ),
                  )
                : WebView(
                    javascriptMode: JavascriptMode.unrestricted,
                    onWebViewCreated: (ctl) {
                      _controller.complete(ctl);
                    },
                    onPageStarted: (url) {
                      setState(() {
                        pageLoading = true;
                        loadingError = false;
                      });
                    },
                    onPageFinished: (String url) {
                      setState(() {
                        navUrl = url;
                        pageLoading = false;
                      });
                    },
                    onWebResourceError: (WebResourceError error) {
                      debugPrint('''
                      Page resource error:
                      code: ${error.errorCode}
                      description: ${error.description}
                      errorType: ${error.errorType}
                      ''');
                    },
                    navigationDelegate: (request) async {
                      if (request.url.contains(widget.returnURL)) {
                        try {
                          final orderId = order?.id ?? "";
                          // await ordersApi.showOrderDetails(orderId);
                          final res = await ordersApi.capturePayment(orderId);
                          if (res.status == "COMPLETED") {
                            await widget.onSuccess(res.toJson());
                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                          debugPrint("capture $res");
                        } catch (e) {
                          debugPrint("error: $e");
                        }
                        return NavigationDecision.navigate;
                      }
                      if (request.url.contains(widget.cancelURL)) {
                        final uri = Uri.parse(request.url);
                        await widget.onCancel(uri.queryParameters);
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                      debugPrint('allowing navigation to ${request.url}');
                      return NavigationDecision.navigate;
                    },
                  ),
      ),
    );
  }
}
