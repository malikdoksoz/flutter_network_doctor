Pod::Spec.new do |s|
  s.name             = 'flutter_network_doctor'
  s.version          = '0.2.0'
  s.summary          = 'Production-grade network diagnostics for Flutter.'
  s.description      = <<-DESC
Structured connectivity, reachability, latency, and native network diagnostics.
                       DESC
  s.homepage         = 'https://github.com/malikdoksoz/flutter_network_doctor'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Malik' => 'malikdoksoz@yandex.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_network_doctor/Sources/flutter_network_doctor/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
