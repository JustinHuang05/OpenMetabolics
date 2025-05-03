import 'package:flutter/material.dart';

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
  OpenEndedQuestion(String questionText) : super(questionText);

  @override
  Widget buildWidget(VoidCallback onChanged, bool submitted) {
    // Keep controller in sync with value
    if (controller.text != (value ?? '')) {
      controller.text = value ?? '';
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    }
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
  ScaleQuestion(String questionText, {this.min = 1, this.max = 10})
      : super(questionText);

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

class FeedbackFormPage extends StatefulWidget {
  @override
  _FeedbackFormPageState createState() => _FeedbackFormPageState();
}

class _FeedbackFormPageState extends State<FeedbackFormPage> {
  final _formKey = GlobalKey<FormState>();
  bool submitted = false;

  late final List<FeedbackQuestion> questions = [
    OpenEndedQuestion(
        '1. What was the activity that you performed throughout your session?:'),
    OpenEndedQuestion(
        '1. What was your self-perceived duration of the activity (in minutes)?:'),
    ScaleQuestion(
        '2. What was your self-percieved intensity when performing the activity (1-10)?'),
  ];

  void _onChanged() {
    setState(() {});
  }

  bool get allAnswered => questions.every((q) => q.isAnswered);

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode:
          submitted ? AutovalidateMode.always : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          SizedBox(height: 20),
          ...questions.expand((q) =>
              [q.buildWidget(_onChanged, submitted), SizedBox(height: 32)]),
          SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color.fromRGBO(216, 194, 251, 1),
              foregroundColor: Colors.black,
              minimumSize: Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: allAnswered
                ? () {
                    setState(() {
                      submitted = true;
                    });
                    if (_formKey.currentState!.validate() && allAnswered) {
                      // Handle submission (e.g., send to backend)
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Thank you!'),
                          content: Text('Your feedback has been submitted.'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  for (var q in questions) {
                                    q.clear();
                                  }
                                  submitted = false;
                                });
                              },
                              child: Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                : null,
            child: Text('Submit'),
          ),
        ],
      ),
    );
  }
}
