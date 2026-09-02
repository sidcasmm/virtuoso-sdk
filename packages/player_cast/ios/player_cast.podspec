Pod::Spec.new do |s|
  s.name             = 'player_cast'
  s.version          = '0.0.1'
  s.summary          = 'Virtuoso Player Cast'
  s.homepage         = 'https://github.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Virtuoso Player' => 'license@local' }
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'Frameworks/player_cast.xcframework'
  s.dependency 'Flutter'
  s.dependency 'google-cast-sdk', '4.8.4'
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
