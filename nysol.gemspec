# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "nysol"
  spec.version       = "3.0.0"
  spec.authors       = ["nysol"]
  spec.email         = ["info@nysol.jp"]
  spec.platform      = Gem::Platform.local
  spec.summary       = %q{Tools for nysol ruby tools}
  spec.description   = %q{refer : http://www.nysol.jp/}
  spec.homepage      = "http://www.nysol.jp/"
	spec.extensions = ['ext/mcsvin/extconf.rb','ext/mcsvout/extconf.rb','ext/mmethods/extconf.rb','ext/mtable/extconf.rb']

	spec.platform = Gem::Platform::RUBY 
  spec.files         = Dir.glob([
		"lib/nysol/*.rb",
		"lib/nysol/mcsvin.*",
		"lib/nysol/mcsvout.*",
		"lib/nysol/mmethods.*",
		"lib/nysol/mtable.*",
		"bin/*.rb" ])
  spec.bindir        = "bin"
  spec.executables   = [
		"meach.rb",
		"meachc.rb",
		"mtempclean.rb",
		"mdistcopy.rb",
		"msend.rb"
 ]
  spec.require_paths = ["lib"]
  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
	spec.add_development_dependency 'rake-compiler'
end
