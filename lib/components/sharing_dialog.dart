import 'package:duration_picker/duration_picker.dart';
import 'package:flutter/material.dart';

class SharingDialog extends StatelessWidget {
  final Duration duration;
  final Function onDurationChange, onStart;

  SharingDialog({this.duration, this.onDurationChange, this.onStart});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Start trekking"),
      content: DurationPicker(
        duration: duration,
        onChange: (d) => onDurationChange(d),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shadowColor: Theme.of(context).accentColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () => onStart(),
          child: Text('Start'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            shadowColor: Theme.of(context).accentColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
      ],
    );
  }
}
