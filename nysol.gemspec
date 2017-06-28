# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "nysol"
  spec.version       = "3.0.1"
  spec.authors       = ["nysol"]
  spec.email         = ["info@nysol.jp"]
  spec.summary       = %q{Tools for nysol ruby tools}
  spec.description   = %q{refer : http://www.nysol.jp/}
  spec.homepage      = "http://www.nysol.jp/"
	spec.extensions = ['ext/mcsvin/extconf.rb','ext/mcsvout/extconf.rb','ext/mmethods/extconf.rb','ext/mtable/extconf.rb']

	spec.platform = Gem::Platform::RUBY 
  spec.files         = Dir.glob([
		"lib/nysol/*.rb",
		"ext/mcsvin/*.rb",
		"ext/mcsvout/*.rb",
		"ext/mmethods/*.rb",
		"ext/mtable/*.rb",
		"ext/mcsvin/*.cpp",
		"ext/mcsvout/*.cpp",
		"ext/mmethods/*.cpp",
		"ext/mtable/*.cpp",
		"bin/*.rb" ])
	spec.extensions=[
		"ext/mcsvin/extconf.rb",
		"ext/mcsvout/extconf.rb",
		"ext/mmethods/extconf.rb",
		"ext/mtable/extconf.rb",
	]
  spec.bindir        = "bin"
  spec.executables   = [
		"meach.rb",
		"meachc.rb",
		"mtempclean.rb",
		"mdistcopy.rb",
		"msend.rb"
 ]
  spec.require_paths = ["lib"]
	spec.add_development_dependency 'rake-compiler'
end
