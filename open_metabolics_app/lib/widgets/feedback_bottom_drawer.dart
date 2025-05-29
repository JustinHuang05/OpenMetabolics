import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth/auth_service.dart';
import '../config/api_config.dart';
import 'package:hive/hive.dart';

const kAppPurple = Color.fromRGBO(216, 194, 251, 1);

abstract class FeedbackQuestion<T> {
  final String questionText;
  T? value;
  FeedbackQuestion(this.questionText);
  Widget buildWidget(VoidCallback onChanged, bool submitted);
  bool get isAnswered;
  void clear();
}

class OpenEndedQuestion extends FeedbackQuestion<String> {
  final TextEditingController controller = TextEditingController();
  OpenEndedQuestion(String questionText, {String? initialValue})
      : super(questionText) {
    if (initialValue != null) {
      value = initialValue;
      controller.text = initialValue;
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    }
  }

  @override
  Widget buildWidget(VoidCallback onChanged, bool submitted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          questionText,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        SizedBox(height: 8),
        TextFormField(
          maxLines: 4,
          controller: controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Type your answer here...',
            fillColor: Colors.grey[100],
            filled: true,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter your answer.';
            }
            return null;
          },
          onChanged: (val) {
            value = val;
            onChanged();
          },
        ),
      ],
    );
  }

  @override
  bool get isAnswered => value != null && value!.trim().isNotEmpty;

  @override
  void clear() {
    value = null;
    controller.clear();
  }
}

class ScaleQuestion extends FeedbackQuestion<int> {
  final int min;
  final int max;
  ScaleQuestion(String questionText,
      {this.min = 1, this.max = 10, int? initialValue})
      : super(questionText) {
    if (initialValue != null) {
      value = initialValue;
    }
  }

  @override
  Widget buildWidget(VoidCallback onChanged, bool submitted) {
    final int itemCount = max - min + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          questionText,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final double totalWidth = constraints.maxWidth;
            final double segmentWidth = totalWidth / itemCount;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                final localDx =
                    details.localPosition.dx.clamp(0, totalWidth - 1);
                if (localDx < segmentWidth * 0.5) {
                  if (value != null) {
                    value = null;
                    onChanged();
                  }
                } else {
                  int newValue =
                      min + ((localDx - segmentWidth * 0.5) ~/ segmentWidth);
                  if (newValue < min) newValue = min;
                  if (newValue > max) newValue = max;
                  if (value != newValue) {
                    value = newValue;
                    onChanged();
                  }
                }
              },
              onTapDown: (details) {
                final localDx =
                    details.localPosition.dx.clamp(0, totalWidth - 1);
                if (localDx < segmentWidth * 0.5) {
                  if (value != null) {
                    value = null;
                    onChanged();
                  }
                } else {
                  int newValue =
                      min + ((localDx - segmentWidth * 0.5) ~/ segmentWidth);
                  if (newValue < min) newValue = min;
                  if (newValue > max) newValue = max;
                  if (value != newValue) {
                    value = newValue;
                    onChanged();
                  }
                }
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black, width: 1.0),
                ),
                child: Row(
                  children: List.generate(itemCount, (index) {
                    int val = min + index;
                    final isSelected = value != null && val <= value!;
                    BorderRadius radius = BorderRadius.zero;
                    if (index == 0) {
                      radius =
                          BorderRadius.horizontal(left: Radius.circular(24));
                    } else if (index == itemCount - 1) {
                      radius =
                          BorderRadius.horizontal(right: Radius.circular(24));
                    }
                    return Expanded(
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 150),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          color: isSelected ? kAppPurple : Colors.transparent,
                          borderRadius: radius,
                        ),
                        padding: EdgeInsets.symmetric(vertical: 0),
                        child: Center(
                          child: Text(
                            '$val',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Theme.of(context).hintColor,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
        if (submitted && value == null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Please select a value.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  @override
  bool get isAnswered => value != null;

  @override
  void clear() {
    value = null;
  }
}

class NumberInputQuestion extends FeedbackQuestion<num> {
  final TextEditingController controller = TextEditingController();
  final String suffix;

  NumberInputQuestion(String questionText,
      {this.suffix = '', num? initialValue})
      : super(questionText) {
    if (initialValue != null) {
      value = initialValue;
      controller.text = initialValue.toString();
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    }
  }

  @override
  Widget buildWidget(VoidCallback onChanged, bool submitted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          questionText,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Enter a number',
            suffixText: suffix,
            fillColor: Colors.grey[100],
            filled: true,
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter a number.';
            }
            if (double.tryParse(val) == null) {
              return 'Please enter a valid number.';
            }
            return null;
          },
          onChanged: (val) {
            if (val.isNotEmpty) {
              value = double.tryParse(val);
            } else {
              value = null;
            }
            onChanged();
          },
        ),
      ],
    );
  }

  @override
  bool get isAnswered => value != null;

  @override
  void clear() {
    value = null;
    controller.clear();
  }
}

class FeedbackBottomDrawer extends StatefulWidget {
  final String? sessionId;
  final Map<String, dynamic>? existingResponse;
  final VoidCallback? onSurveySubmitted;

  const FeedbackBottomDrawer({
    Key? key,
    this.sessionId,
    this.existingResponse,
    this.onSurveySubmitted,
  }) : super(key: key);

  @override
  _FeedbackBottomDrawerState createState() => _FeedbackBottomDrawerState();
}

class _FeedbackBottomDrawerState extends State<FeedbackBottomDrawer> {
  final _formKey = GlobalKey<FormState>();
  bool submitted = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    print(
        'FeedbackBottomDrawer initState with response: ${widget.existingResponse}');
  }

  late final List<FeedbackQuestion> questions = [
    OpenEndedQuestion(
      '1. What was the activity that you performed throughout your session?:',
      initialValue:
          widget.existingResponse?['Responses']?['question_1']?.toString(),
    ),
    NumberInputQuestion(
      '2. What was your self-perceived duration of the activity?:',
      suffix: 'min',
      initialValue: widget.existingResponse?['Responses']?['question_2'] != null
          ? double.tryParse(
              widget.existingResponse!['Responses']!['question_2'].toString())
          : null,
    ),
    ScaleQuestion(
      '3. What was your self-percieved intensity when performing the activity (1-10)?',
      initialValue: widget.existingResponse?['Responses']?['question_3'] != null
          ? int.tryParse(
              widget.existingResponse!['Responses']!['question_3'].toString())
          : null,
    ),
  ];

  void _onChanged() {
    setState(() {});
  }

  bool get allAnswered => questions.every((q) => q.isAnswered);

  Future<void> _submitSurvey() async {
    if (!_formKey.currentState!.validate() || !allAnswered) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final userEmail = await AuthService().getCurrentUserEmail();
      if (userEmail == null) {
        throw Exception('User not logged in');
      }

      // Prepare the responses
      final responses = {
        for (var i = 0; i < questions.length; i++)
          'question_${i + 1}': questions[i].value.toString()
      };

      final response = await http.post(
        Uri.parse(ApiConfig.saveSurveyResponse),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_email': userEmail,
          'responses': responses,
          'questions': questions.map((q) => q.questionText).toList(),
          'session_id': widget.sessionId,
        }),
      );

      if (response.statusCode == 200) {
        // Update Hive cache to mark this session as having a survey response
        if (widget.sessionId != null) {
          final box = Hive.box('session_summaries');
          final sessions = box.get('all_sessions', defaultValue: []) as List;
          for (var session in sessions) {
            if (session['sessionId'] == widget.sessionId) {
              session['hasSurveyResponse'] = true;
              break;
            }
          }
          await box.put('all_sessions', sessions);
        }
        if (mounted) {
          // Dismiss keyboard
          FocusScope.of(context).unfocus();

          // Notify parent that survey was submitted
          widget.onSurveySubmitted?.call();

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Thank you!'),
              content: Text('Your survey has been submitted.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(); // Close bottom drawer
                  },
                  child: Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception('Failed to submit survey: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Session Survey',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Form
          Flexible(
            child: Form(
              key: _formKey,
              autovalidateMode: submitted
                  ? AutovalidateMode.always
                  : AutovalidateMode.disabled,
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  left: 20.0,
                  right: 20.0,
                  top: 20.0,
                  bottom: isKeyboardVisible ? bottomInset + 20.0 : 20.0,
                ),
                children: [
                  ...questions.expand((q) => [
                        q.buildWidget(_onChanged, submitted),
                        SizedBox(height: 32)
                      ]),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAppPurple,
                      foregroundColor: Colors.black,
                      minimumSize: Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting || !allAnswered
                        ? null
                        : () {
                            setState(() {
                              submitted = true;
                            });
                            _submitSurvey();
                          },
                    child: _isSubmitting
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : Text('Submit'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
