import 'dart:async';
// import 'dart:js';
// import 'dart:ui';

import 'package:PhotoWordFind/main.dart';
import 'package:catcher/catcher.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/src/widgets/framework.dart';
import 'package:progress_dialog/progress_dialog.dart';

Widget dialog;
BuildContext _progressContext, _messageContext;
GlobalKey<NavigatorState> _navigatorKey;

class MyProgressDialog extends ProgressDialog{
  Timer _scheduleTimeout;
  MyProgressDialog(BuildContext context, GlobalKey navigatorKey,
      {ProgressDialogType type,
        bool isDismissible,
        bool showLogs,
        TextDirection textDirection,
        Widget customBody}) : super(context,type:type,
      isDismissible:isDismissible,
      showLogs:showLogs,
      textDirection:textDirection,
      customBody:customBody) {
    _progressContext = context;
    // _navigatorKey = navigatorKey;
  }

  Future<bool> show() async{
    bool ret = await super.show();

    // Make sure previous timer no longer exists before creating new one
    if(_scheduleTimeout != null && _scheduleTimeout.isActive)
      _scheduleTimeout.cancel();

    _scheduleTimeout = _createTimer();
    return ret;
  }

  Future<bool> hide() async {
    debugPrint("Entering hide...");
    _scheduleTimeout.cancel();

    _removeMessage();
    bool ret = await super.hide();

    debugPrint("Leaving hide...");
    return ret;
  }

  void _handleTimeout(){
    debugPrint("Entering _handleTimeout...");
    showDialog(context: _progressContext, builder: (context) => timeoutDialog(context), barrierDismissible: false);

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      debugPrint("message: $_messageContext");
      debugPrint("progress: $_progressContext");
    });
    debugPrint("Leaving _handleTimeout...");
  }
  
  void _stopProgressBar() async{
    debugPrint("Entering _stopProgressBar...");
    debugPrint("is showing: ${this.isShowing()}");
    WidgetsBinding.instance
        .addPostFrameCallback((_) => throw TimeoutException("Progress bar is taking longer than expected"));
    await this.hide();
    debugPrint("Leaving _stopProgressBar...");
  }

  void _removeMessage(){
    debugPrint("Entering _removeMessage...");
    if(_messageContext != null){
      // Check if context of message is present
      try{
        ModalRoute.of(_messageContext);
        if(ModalRoute.of(_messageContext).isCurrent) {
          debugPrint(
              "ModalRoute.of(context)?.isCurrent: ${ModalRoute.of(_messageContext)?.isCurrent}");
          Navigator.of(_messageContext).pop();
        }
      }
      catch(e){}
    }
    debugPrint("Leaving _removeMessage...");
  }
  
  void _keepWaiting(){
    debugPrint("Entering _keepWaiting...");
    if(this.isShowing())
      _scheduleTimeout = _createTimer();
    Navigator.of(_messageContext).pop();
    debugPrint("Entering _keepWaiting...");
  }

  Timer _createTimer(){
    return Timer(Duration(seconds: 8), _handleTimeout);;
  }

  Widget timeoutDialog(BuildContext context){
    _messageContext = context;
    if(dialog == null)
      dialog = Center(
      child: Wrap(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
            ),
            child: Column(
              children: [
                SizedBox(height: 10),
                Text(
                  "Process is taking longer than expected",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.deepPurple,
                    backgroundColor: Colors.black.withOpacity(0.1),
                    fontSize: 20,
                    decoration: TextDecoration.none,
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(child: SizedBox(), flex: 1,),
                    Expanded(
                      flex: 3,
                      child: Container(
                        width: MediaQuery.of(_progressContext).size.width,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          // crossAxisAlignment: CrossAxisAlignment.sp,
                          children: [
                            ElevatedButton(
                              onPressed: _keepWaiting,
                              child: Text("Keep waiting..."),
                            ),
                            ElevatedButton(
                              onPressed: _stopProgressBar,
                              child: Text("Stop..."),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(padding: EdgeInsets.only(right: 20)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return dialog;
  }
}