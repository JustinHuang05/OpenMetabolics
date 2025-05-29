import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SignUpTf extends StatefulWidget {
  String label;
  String hintText;
  TextEditingController controller;
  bool error;
  String errorText;
  Color warningColor;
  Function() errorCheck;
  bool isEmail;

  SignUpTf(this.label, this.hintText, this.controller, this.error,
      this.errorText, this.warningColor, this.errorCheck, this.isEmail);

  @override
  State<SignUpTf> createState() => _SignUpTfState();
}

class _SignUpTfState extends State<SignUpTf> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.normal,
            fontSize: 14,
            color: widget.error
                ? Color.fromRGBO(252, 48, 48, 1)
                : Color.fromRGBO(66, 66, 66, 1),
          ),
        ),
        SizedBox(height: 3),
        Container(
          height: 52,
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: widget.error
                    ? Color.fromRGBO(252, 48, 48, 1)
                    : Color.fromRGBO(216, 194, 251, 1),
                width: widget.error ? 3 : 1.5,
              ),
            ),
            child: TextField(
              obscureText: widget.isEmail ? false : true,
              onChanged: (_) {
                widget.errorCheck();
              },
              controller: widget.controller,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.normal,
                fontSize: 14,
                color: Color.fromRGBO(66, 66, 66, 1),
              ),
              keyboardType: widget.isEmail ? TextInputType.emailAddress : null,
              maxLines: 1,
              cursorColor: Color.fromRGBO(216, 194, 251, 1),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.normal,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  color: Color.fromRGBO(158, 158, 158, 1),
                ),
                contentPadding: EdgeInsets.only(left: 14, right: 14, bottom: 6),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        Container(
          margin: EdgeInsets.only(left: 3.5),
          child: Text(
            widget.errorText,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.normal,
              fontSize: 9,
              color: widget.error
                  ? Color.fromRGBO(252, 48, 48, 1)
                  : widget.warningColor,
            ),
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }
}
