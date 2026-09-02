## 0.0.1

* `AdsClient.bind` requests a VAST/VMAP tag on a `PlayerController` before
  `load`. Pre / mid / post rolls play through Google IMA (Media3
  `ImaAdsLoader` / iOS IMA SDK). `AdsView` is the IMA overlay.
* HTTP(S) tags only. A correlator is appended when the tag omits one.
* Tag failure sets `AdState.error`; content still plays.
