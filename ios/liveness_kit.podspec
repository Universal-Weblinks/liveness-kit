#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint liveness_kit.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'liveness_kit'
  s.version          = '0.1.0'
  s.summary          = 'Gesture-based face liveness check for Flutter.'
  s.description      = <<-DESC
Head-turn challenges, a still at the end, and native face detection —
Apple Vision on iOS — with no Firebase and no ML Kit.
                       DESC
  s.homepage         = 'https://github.com/Universal-Weblinks/liveness-kit'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Universal Weblinks' => 'universalweblinksteam@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Vision ships with iOS; naming it here keeps the link explicit rather than
  # relying on the host app's build settings.
  s.frameworks = 'Vision', 'CoreImage'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'liveness_kit_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
