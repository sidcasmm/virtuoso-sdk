Pod::Spec.new do |s|
  s.name             = 'player_core'
  s.version          = '0.0.1'
  s.summary          = 'Virtuoso Player engine'
  s.homepage         = 'https://github.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Virtuoso Player' => 'license@local' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'Frameworks/player_core.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.frameworks = 'AVFoundation', 'AVKit', 'MediaPlayer'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
