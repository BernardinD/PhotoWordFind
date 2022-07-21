import 'dart:async';
// import 'dart:js';
// import 'dart:ui';

import 'package:PhotoWordFind/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/src/widgets/framework.dart';
import 'package:progress_dialog/progress_dialog.dart';

BuildContext _context;

class MyProgressDialog extends ProgressDialog{
  Timer _scheduleTimeout;
  MyProgressDialog(BuildContext context,
      {ProgressDialogType type,
        bool isDismissible,
        bool showLogs,
        TextDirection textDirection,
        Widget customBody}) : super(context,type:type,
      isDismissible:isDismissible,
      showLogs:showLogs,
      textDirection:textDirection,
      customBody:customBody) {
    _context = context;;
  }

  Future<bool> show() async{
    bool ret = await super.show();
    _scheduleTimeout = Timer(Duration(seconds: 8), _handleTimeout);
    return ret;
  }

  Future<bool> hide() async {
    debugPrint("Entering hide...");
    _scheduleTimeout.cancel();
    bool ret = await super.hide();
    debugPrint("Leaving hide...");
    return ret;
  }

  void _handleTimeout(){
    debugPrint("Entering _handleTimeout...");
    showDialog(context: _context, builder: (context) => timeoutDialog(), barrierDismissible: false);
    debugPrint("Leaving _handleTimeout...");
  }
  
  void _stopProgressBar() async{
    debugPrint("Entering _stopProgressBar...");
    debugPrint("is showing: ${this.isShowing()}");
    Navigator.of(_context).pop();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => throw TimeoutException("Progress bar is taking longer than expected"));
    await this.hide();
    debugPrint("Leaving _stopProgressBar...");
  }
  
  void _keepWaiting(){
    debugPrint("Entering _keepWaiting...");
    if(this.isShowing())
      _scheduleTimeout = Timer(Duration(seconds: 8), _handleTimeout);
    Navigator.of(_context).pop();
    debugPrint("Entering _keepWaiting...");
  }

  Widget timeoutDialog(){
    return Center(
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
                        width: MediaQuery.of(_context).size.width,
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
  }
}