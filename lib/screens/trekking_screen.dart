import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share/share.dart';
import 'package:the_trekking_app/components/sharing_dialog.dart';

class TrekkingScreen extends StatefulWidget {
  final String passKey, name, title;

  TrekkingScreen({this.passKey, this.name, this.title})
      : assert(passKey != null && name != null);

  @override
  _TrekkingScreenState createState() => _TrekkingScreenState();
}

class _TrekkingScreenState extends State<TrekkingScreen> {
  var _firestore = FirebaseFirestore.instance;
  var beaconCarrier = '';
  var _start = 0;
  var _markers = Set<Marker>();
  var _loadingDynamicLink = false;

  var duration = Duration(seconds: 0);

  Completer<GoogleMapController> _controller = Completer();

  static final CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  _stopTimer() {
    setState(() {
      _start = 0;
      duration = Duration(seconds: 0);
    });
  }

  _startTimer() {
    setState(() {
      _start = duration.inSeconds;
    });
    const oneSec = Duration(seconds: 1);
    Timer.periodic(
      oneSec,
      (Timer timer) async {
        if (_start == 0) {
          setState(() {
            timer.cancel();
          });

          await _firestore
              .collection('treks')
              .doc(widget.passKey)
              .update({'location': GeoPoint(0, 0)});
        } else {
          // Sharing user's location
          _determinePosition();
          setState(() {
            _start--;
          });
        }
      },
    );
    Navigator.pop(context);
  }

  _shareInvitation() async {
    setState(() {
      _loadingDynamicLink = true;
    });
    // generate a short url using the passkey
    final DynamicLinkParameters parameters = DynamicLinkParameters(
      uriPrefix: 'https://trekkingapp.page.link',
      link: Uri.parse('https://example.com/?passKey=${widget.passKey}'),
      androidParameters: AndroidParameters(
        packageName: 'com.tusharojha.the_trekking_app',
      ),
      socialMetaTagParameters: SocialMetaTagParameters(
        title: "Let's start a trek.",
        description: "Invitation for ${widget.title}'s trek",
      ),
    );

    final ShortDynamicLink shortDynamicLink = await parameters.buildShortLink();
    final Uri shortUrl = shortDynamicLink.shortUrl;

    // Sharing the shorten url.
    Share.share(
        'Join my trek! \nPassKey: ${widget.passKey} \n${shortUrl.toString()}');
    setState(() {
      _loadingDynamicLink = false;
    });
  }

  _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        // Permissions are denied forever, handle appropriately.
        return Fluttertoast.showToast(
            msg:
                'Location permissions are permanently denied, we cannot request your location.');
      }

      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.

        return Fluttertoast.showToast(
            msg:
                'Location permission is denied, we cannot request your location.');
      }
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    var position = await Geolocator.getCurrentPosition();

    // Updating the location to firebase cloud storage.
    await _firestore.collection('treks').doc(widget.passKey).update({
      'location': GeoPoint(position.latitude, position.longitude),
    });
  }

  // Animate the camera to new position.
  animateCamera(CameraPosition beaconPosition) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(beaconPosition));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.title}'s Trek"),
        leading: IconButton(
          onPressed: () async {
            if (beaconCarrier == widget.name) {
              // Deleting the trek from firebase cloudstore.
              try {
                await _firestore
                    .collection('treks')
                    .doc(widget.passKey)
                    .update({'active': false});
                await _firestore
                    .collection('treks')
                    .doc(widget.passKey)
                    .delete();
              } catch (e) {
                Fluttertoast.showToast(msg: e.toString());
              }
            } else {
              // Removing the user from members list.
              try {
                var doc = await _firestore
                    .collection('treks')
                    .doc(widget.passKey)
                    .get();
                var members = doc
                    .data()['members']
                    .where((name) => name != widget.name)
                    .toList();
                await _firestore
                    .collection('treks')
                    .doc(widget.passKey)
                    .update({'members': members});
                Navigator.pop(context);
              } catch (e) {
                Fluttertoast.showToast(msg: e.toString());
              }
            }
          },
          icon: Icon(Icons.close),
          color: Colors.white,
        ),
        actions: [
          _loadingDynamicLink
              ? Container(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    valueColor: new AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.share),
                  onPressed: () => _shareInvitation(),
                ),
        ],
      ),
      body: StreamBuilder(
        stream: _firestore.collection('treks').doc(widget.passKey).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(),
            );
          }
          var trekRecord = snapshot.data;
          beaconCarrier = trekRecord['beaconCarrier'];

          // Checks if the trekking instance is deleted by the beacon carrier.
          if (trekRecord['active'] == false) {
            Fluttertoast.showToast(msg: 'Trekking is completed!');
            Navigator.pop(context);
          }

          // Get's the beacon carrier current position.
          var beaconPosition;
          if (trekRecord['location'] != null) {
            GeoPoint location = trekRecord['location'];
            beaconPosition = CameraPosition(
                target: LatLng(location.latitude, location.longitude),
                zoom: 19.0);
            _markers.clear();
            _markers.add(Marker(
              markerId: MarkerId('location'),
              position: LatLng(location.latitude, location.longitude),
              infoWindow: InfoWindow(snippet: "$beaconCarrier's position"),
            ));
            animateCamera(beaconPosition);
          }
          return Column(
            children: [
              Container(
                height: 300,
                child: GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: beaconPosition ?? _kGooglePlex,
                  markers: _markers,
                  onMapCreated: (GoogleMapController controller) {
                    _controller.complete(controller);
                  },
                ),
              ),
              InkWell(
                onTap: widget.name == trekRecord['beaconCarrier']
                    ? () {
                        if (_start == 0) {
                          // Dialog box to start sharing and ask for a timer.
                          showDialog(
                            context: context,
                            builder: (_) => StatefulBuilder(
                              builder: (context, setState) => SharingDialog(
                                duration: duration,
                                onDurationChange: (d) => setState(() {
                                  duration = d;
                                }),
                                onStart: () => _startTimer(),
                              ),
                            ),
                          );
                        } else {
                          // Dialog box to show remaining time and dismiss sharing.
                          showDialog(
                            context: context,
                            builder: (_) => StatefulBuilder(
                              builder: (context, setState) => AlertDialog(
                                title: Text('Stop trekking'),
                                content: Text(
                                    'Remaining Time: ${Duration(seconds: _start).inMinutes} mins.'),
                                actions: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      shadowColor:
                                          Theme.of(context).accentColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    onPressed: () {
                                      _stopTimer();
                                      Navigator.pop(context);
                                    },
                                    child: Text('Stop'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      shadowColor:
                                          Theme.of(context).accentColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                    child: Text('Cancel'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }
                    : null,
                child: Container(
                  padding: EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Text(
                        'Location Sharing',
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).accentColor,
                        ),
                      ),
                      Spacer(),
                      Icon(
                        Icons.check_circle,
                        color: (trekRecord['location'] as GeoPoint).longitude ==
                                    0 &&
                                (trekRecord['location'] as GeoPoint).latitude ==
                                    0
                            ? Colors.grey
                            : Colors.green,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemBuilder: (context, i) => Container(
                    child: InkWell(
                      onLongPress: widget.name == trekRecord['beaconCarrier']
                          ? () async {
                              // Beacon carrier can handover the beacon to another member.
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Text('Are you sure?'),
                                  content: Text(
                                      'Are you sure you want to handover the beacon to ${trekRecord['members'][i]}?'),
                                  actions: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        shadowColor:
                                            Theme.of(context).accentColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                      ),
                                      onPressed: () async {
                                        await _firestore
                                            .collection('treks')
                                            .doc(widget.passKey)
                                            .update({
                                          'beaconCarrier': trekRecord['members']
                                              [i],
                                          'location': GeoPoint(0, 0),
                                        });

                                        setState(() {
                                          _start = 0;
                                          duration = Duration(seconds: 0);
                                        });
                                        Navigator.pop(context);
                                      },
                                      child: Text('Yes'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        shadowColor:
                                            Theme.of(context).accentColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                      ),
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('No'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          : null,
                      child: Container(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Text(
                              trekRecord['members'][i].toString(),
                              style: TextStyle(
                                fontSize: 20,
                              ),
                            ),
                            Spacer(),
                            trekRecord['members'][i] ==
                                    trekRecord['beaconCarrier']
                                ? Icon(
                                    Icons.location_pin,
                                    color: Theme.of(context).accentColor,
                                  )
                                : Container(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  itemCount: trekRecord['members'].length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
