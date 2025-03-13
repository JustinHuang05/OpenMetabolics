import 'package:flutter/material.dart';

class LoginTf extends StatefulWidget {
  String label;
  String hintText;
  TextEditingController controller;
  bool error;
  String errorText;
  bool isEmail;

  LoginTf(this.label, this.hintText, this.controller, this.error,
      this.errorText, this.isEmail);

  @override
  State<LoginTf> createState() => _LoginTfState();
}

class _LoginTfState extends State<LoginTf> {
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
            fontSize: 18,
            color: widget.error
                ? Color.fromRGBO(252, 48, 48, 1)
                : Color.fromRGBO(255, 255, 255, 1),
          ),
        ),
        SizedBox(height: 3),
        Container(
          height: 70,
          child: Card(
            elevation: 0,
            color: Color.fromRGBO(66, 66, 66, 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(
                color: widget.error
                    ? Color.fromRGBO(252, 48, 48, 1)
                    : Color.fromRGBO(255, 255, 255, 1),
                width: widget.error ? 3 : 1.5,
              ),
            ),
            child: TextField(
              obscureText: widget.isEmail ? false : true,
              controller: widget.controller,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.normal,
                fontSize: 18,
                color: Color.fromRGBO(255, 255, 255, 1),
              ),
              keyboardType: widget.isEmail ? TextInputType.emailAddress : null,
              maxLines: 1,
              cursorColor: Color.fromRGBO(255, 255, 255, 1),
              decoration: InputDecoration(
                filled: true,
                fillColor: Color.fromRGBO(66, 66, 66, 1),
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.normal,
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  color: Color.fromRGBO(158, 158, 158, 1),
                ),
                contentPadding: EdgeInsets.only(left: 14, right: 14, top: 12),
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
              fontSize: 12,
              color: widget.error
                  ? Color.fromRGBO(252, 48, 48, 1)
                  : Colors.transparent,
            ),
          ),
        ),
        Container(height: 15),
      ],
    );
  }
}
