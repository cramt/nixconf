require 'bundler'
require 'json'

lock = Bundler::LockfileParser.new(File.read('./Gemfile.lock'))
puts(lock.specs.to_h do |x|
  raise('unsupported for now') unless x.source.is_a? Bundler::Source::Rubygems

  [x.name, {
    version: x.version,
    platform: x.platform,
    source: {

      sha256: [[Bundler::Checksum.from_lock(
        x.source.checksum_store.to_lock(
          x
        ),
        './Gemfile.lock'
      ).digest].pack('H*')].pack('m0'),
      remotes: x.source.remotes.map { |remote| remote.to_s.sub(%r{/+$}, '') },
      type: 'gem'
    }
  }]
end.to_json)
