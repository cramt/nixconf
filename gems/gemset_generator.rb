# frozen_string_literal: true

require 'bundler'
require 'json'

lock = Bundler::LockfileParser.new(File.read('./Gemfile.lock'))
platforms = lock.platforms.map(&:to_s)

def make_source_def(source)
  {
    platform: source.platform,
    sha256: [[Bundler::Checksum.from_lock(
      source.source.checksum_store.to_lock(
        source
      ),
      './Gemfile.lock'
    ).digest].pack('H*')].pack('m0'),

    remotes: source.source.remotes.map { |remote| remote.to_s.sub(%r{/+$}, '') },
    type: 'gem'
  }
end

puts(platforms.to_h do |platform|
  [platform, lock.specs.filter_map do |x|
    if x.platform.to_s == platform

      case x.source
      when Bundler::Source::Rubygems
        [x.name, {
          version: x.version,
          platforms: [],
          source: make_source_def(x)
        }]
      else
        pp spec
        throw 'unsupported bundler source'
      end
    end
  end.to_h]
end.to_json)
