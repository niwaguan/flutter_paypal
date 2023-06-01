library flutter_paypal;

import 'dart:async';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter_paypal/src/screens/complete_payment.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'src/PaypalServices.dart';
import 'src/errors/network_error.dart';

class UsePaypal extends StatefulWidget {
  final Function onSuccess, onCancel, onError;
  final String returnURL, cancelURL, note, clientId, secretKey;
  final List transactions;
  final bool sandboxMode;
  const UsePaypal({
    Key? key,
    required this.onSuccess,
    required this.onError,
    required this.onCancel,
    required this.returnURL,
    required this.cancelURL,
    required this.transactions,
    required this.clientId,
    required this.secretKey,
    this.sandboxMode = false,
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
  String accessToken = '';
  bool loading = true;
  bool pageLoading = true;
  bool loadingError = false;
  late PaypalServices services;
  int pressed = 0;

  Map getOrderParams() {
    Map<String, dynamic> temp = {
      "intent": "sale",
      "payer": {"payment_method": "paypal"},
      "transactions": widget.transactions,
      "note_to_payer": widget.note,
      "redirect_urls": {
        "return_url": widget.returnURL,
        "cancel_url": widget.cancelURL
      }
    };
    return temp;
  }

  loadPayment() async {
    setState(() {
      loading = true;
    });
    try {
      Map getToken = await services.getAccessToken();
      if (getToken['token'] != null) {
        accessToken = getToken['token'];
        final transactions = getOrderParams();
        final res =
            await services.createPaypalPayment(transactions, accessToken);
        if (res["approvalUrl"] != null) {
          setState(() {
            checkoutUrl = res["approvalUrl"].toString();
            navUrl = res["approvalUrl"].toString();
            executeUrl = res["executeUrl"].toString();
            loading = false;
            pageLoading = false;
            loadingError = false;
          });
          (await _controller.future).loadUrl(checkoutUrl);
        } else {
          widget.onError(res);
          setState(() {
            loading = false;
            pageLoading = false;
            loadingError = true;
          });
        }
      } else {
        widget.onError("${getToken['message']}");

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
    services = PaypalServices(
      sandboxMode: widget.sandboxMode,
      clientId: widget.clientId,
      secretKey: widget.secretKey,
    );
    setState(() {
      navUrl = widget.sandboxMode
          ? 'https://api.sandbox.paypal.com'
          : 'https://www.api.paypal.com';
    });
    // Enable hybrid composition.
    loadPayment();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (pressed < 2) {
          setState(() {
            pressed++;
          });
          final snackBar = SnackBar(
              content: Text(
                  'Press back ${3 - pressed} more times to cancel transaction'));
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
          return false;
        } else {
          return true;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          leading: GestureDetector(
            child: const Icon(Icons.arrow_back_ios),
            onTap: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        color: Uri.parse(navUrl).hasScheme
                            ? Colors.green
                            : Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          navUrl,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      SizedBox(width: pageLoading ? 5 : 0),
                      pageLoading
                          ? const SpinKitFadingCube(
                              color: Color(0xFFEB920D),
                              size: 10.0,
                            )
                          : const SizedBox()
                    ],
                  ),
                ),
              )
            ],
          ),
          elevation: 0,
        ),
        body: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          child: loading
              ? const Center(
                  child: SpinKitFadingCube(
                    color: Color(0xFFEB920D),
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
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CompletePayment(
                                url: request.url,
                                services: services,
                                executeUrl: executeUrl,
                                accessToken: accessToken,
                                onSuccess: widget.onSuccess,
                                onCancel: widget.onCancel,
                                onError: widget.onError,
                              ),
                            ),
                          );
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
      ),
    );
  }
}
