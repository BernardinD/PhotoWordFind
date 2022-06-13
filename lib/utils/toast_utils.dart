
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:fluttertoast/fluttertoast.dart';

class Toasts{
  Toasts._internal();
  static final Toasts _singleton = Toasts._internal();

  static FToast _fToast;
  factory Toasts(){
    return _singleton;
  }

  static void initToasts(BuildContext context){
    _fToast = FToast();
    _fToast.init(context);
  }

  /// Displays a Toast of the `selection` state of the current visible Cell in the gallery
  static void showToast(bool state, Function message){

    // Make sure last toast has eneded
    _fToast.removeCustomToast();

    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: state ? Colors.greenAccent : Colors.grey,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          state ? Icon(Icons.check) : Icon(Icons.not_interested_outlined),
          SizedBox(
            width: 12.0,
          ),
          Text(message(state)),
        ],
      ),
    );



    _fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 1),
    );
  }
}