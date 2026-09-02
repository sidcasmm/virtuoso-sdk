Pod::Spec.new do |s|
  s.name             = 'player_ads'
  s.version          = '0.0.1'
  s.summary          = 'Virtuoso Player ads'
  s.homepage         = 'https://github.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Virtuoso Player' => 'license@local' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'Frameworks/player_ads.xcframework'
  s.dependency 'Flutter'
  s.dependency 'player_core'
  s.dependency 'GoogleAds-IMA-iOS-SDK', '~> 3.23'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
