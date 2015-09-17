Pod::Spec.new do |s|
  s.name             	= "BSMediaExporter"
  s.version          	= "1.1.0"
  s.summary          	= "Methods for exporting and converting media files"
  s.description      	= "Useful methods for export and convert media files"
 s.homepage         	= "https://github.com/Bogdan-Stasjuk/BSMediaExporter"
  s.license      		= { :type => 'MIT', :file => 'LICENSE' }
  s.author           	= { "Bogdan Stasiuk" => "Bogdan.Stasjuk@gmail.com" }
  s.source           	= { :git => "https://github.com/Bogdan-Stasjuk/BSMediaExporter.git", :tag => '1.1.0' }
  s.social_media_url 	= 'https://twitter.com/Bogdan_Stasjuk'
  s.platform     		= :ios, '7.0'
  s.requires_arc 	= true
  s.source_files 	= 'BSMediaExporter/*.{h,m}'
  s.public_header_files   	= 'BSMediaExporter/*.h'
  s.dependency 'BSMacros'
  s.dependency 'BSAudioFileHelper'
  s.dependency 'NSFileManager+Helper'
end
