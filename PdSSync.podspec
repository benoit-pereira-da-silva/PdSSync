Pod::Spec.new do |s|
  s.name        = 'PdSSync'
  s.version     = '1.1.1'
  s.authors     = { 'Benoit Pereira da Silva' => 'benoit@pereira-da-silva.com' }
  s.homepage    = 'https://github.com/benoit-pereira-da-silva/PdSSync'
  s.summary     = 'A simple delta synchronizer'
  s.source      = { :git => 'https://github.com/benoit-pereira-da-silva/PdSSync.git',:branch=>'master'}
  s.license     = { :type => "LGPL", :file => "LICENSE" }

  s.ios.deployment_target = '7.0'
  s.osx.deployment_target = '10.9'
  s.dependency 'AFNetworking', '~>2.5'
  s.requires_arc = true
  s.source_files =  'PdSSync/*.{h,m}'
  s.public_header_files = 'PdSSync/**/*.h'

  # WOULD LIKE TO ADD A DEPENDENCY to PdSCommons (required)
  #s.dependency 'PdSCommons',{ :git => 'https://github.com/benoit-pereira-da-silva/PdSCommons.git',:branch=>'master'}

end
