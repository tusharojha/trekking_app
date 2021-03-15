import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'components/header.dart';
import 'screens/trekking_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Trekking App',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  TextEditingController _name, _code, nameController;
  bool _loading = false;

  var _firestore = FirebaseFirestore.instance;

  void initDynamicLinks() async {
    FirebaseDynamicLinks.instance.onLink(
        onSuccess: (PendingDynamicLinkData dynamicLink) async {
      final Uri deepLink = dynamicLink?.link;

      if (deepLink != null) {
        var passKey = deepLink.queryParameters['passKey'];
        if (passKey != null && passKey != '') {
          _joinTrek(passKey: passKey);
        }
      }
    }, onError: (OnLinkErrorException e) async {
      print('onLinkError');
      print(e.message);
    });

    final PendingDynamicLinkData data =
        await FirebaseDynamicLinks.instance.getInitialLink();
    final Uri deepLink = data?.link;

    if (deepLink != null) {
      var passKey = deepLink.queryParameters['passKey'];
      if (passKey != null && passKey != '') {
        _joinTrek(passKey: passKey);
      }
    }
  }

  @override
  initState() {
    super.initState();
    _name = TextEditingController();
    _code = TextEditingController();
    nameController = TextEditingController();
    initDynamicLinks();
  }

  @override
  dispose() {
    _name.dispose();
    _code.dispose();
    nameController.dispose();
    super.dispose();
  }

  _joinTrek({String passKey}) async {
    if (_code.text == '' && passKey == null) {
      Fluttertoast.showToast(msg: 'Joining code is mandatory.');
      return;
    }

    // Checking if the trek is still active or not.
    var document =
        await _firestore.collection('treks').doc(passKey ?? _code.text).get();
    if (!document.exists || document.data()['active'] == false) {
      Fluttertoast.showToast(msg: "Trek doesn't exists!");
      return;
    }

    // Prompting user to enter name to start trekking.
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${document.data()['beaconCarrier']}'s Trek"),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Enter your name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).accentColor),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shadowColor: Theme.of(context).accentColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () async {
              if (nameController.text.length < 4) {
                Fluttertoast.showToast(msg: 'Name is a required property');
                return;
              }

              // Updating members list and navigating user to the trekking screen.
              setState(() {
                _loading = true;
              });
              Navigator.pop(context);
              await _firestore
                  .collection('treks')
                  .doc(passKey ?? _code.text)
                  .update({
                'members': FieldValue.arrayUnion([nameController.text])
              });
              setState(() {
                _loading = false;
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TrekkingScreen(
                    passKey: passKey ?? _code.text,
                    name: nameController.text,
                    title: document.data()['beaconCarrier'],
                  ),
                ),
              );
            },
            child: Text('Join'),
          )
        ],
      ),
    );
  }

  _createTrek() async {
    if (_name.text == '' || _name.text.length < 4) {
      Fluttertoast.showToast(msg: 'Name is a required property.');
      return;
    }

    // Popping off the alert dialog.
    Navigator.pop(context);

    // Creating a trek and navigating user to trekking screen.
    setState(() {
      _loading = true;
    });
    try {
      var trek = await _firestore.collection('treks').add({
        'members': [_name.text],
        'beaconCarrier': _name.text,
        'location': GeoPoint(0, 0),
        'active': true,
      });
      String passKey = trek.id;
      setState(() {
        _loading = false;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrekkingScreen(
              passKey: passKey, name: _name.text, title: _name.text),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: Column(
            children: [
              Header(),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: _code,
                        decoration: InputDecoration(
                          labelText: 'Enter Team Code',
                          suffixIcon: IconButton(
                            onPressed: () async {
                              ClipboardData data =
                                  await Clipboard.getData('text/plain');
                              setState(() {
                                _code.text = data.text.toString();
                              });
                            },
                            icon: Icon(Icons.paste),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Theme.of(context).accentColor),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          shadowColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _loading ? null : _joinTrek,
                        child: Container(
                          child: Text(_loading ? 'Loading...' : 'Join Trek'),
                          padding: EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text('Create a new Trek'),
                              content: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: TextField(
                                  controller: _name,
                                  decoration: InputDecoration(
                                    labelText: 'Enter your name',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Theme.of(context).accentColor),
                                    ),
                                  ),
                                ),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed:
                                      _loading ? null : () => _createTrek(),
                                  style: ElevatedButton.styleFrom(
                                    shadowColor: Theme.of(context).accentColor,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check,
                                        color: Colors.white,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text('Done'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Don't have a team code? "),
                            Text(
                              "Create New.",
                              style: TextStyle(
                                  color: Theme.of(context).accentColor),
                            )
                          ],
                        ),
                      ),
                    ),
                    Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text('Developed with ❤ by Tushar Ojha'),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
