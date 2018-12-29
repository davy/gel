# frozen_string_literal: true

require "set"

require_relative "../pinboard"

require_relative "common"

class Paperback::Catalog::CompactIndex
  include Paperback::Catalog::Common

  def initialize(uri, uri_identifier, httpool:, work_pool:)
    super

    @gem_tokens = Hash.new("NONE")
    @needs_update = true
    @updating = false
    @active_gems = Set.new
    @pending_gems = Set.new
  end

  def update
    @monitor.synchronize do
      return false unless @needs_update
      @needs_update = false
      @updating = true
    end

    error = lambda do |ex|
      @monitor.synchronize do
        @error = ex
        @refresh_cond.broadcast
      end
    end

    pinboard.async_file(uri("versions"), tail: true, error: error) do |f|
      new_tokens = {}

      started = false
      f.each_line do |line|
        unless started
          started ||= line == "---\n"
          next
        end
        line.chop!

        name, _versions, token = line.split
        new_tokens[name] = token
      end

      @monitor.synchronize do
        @gem_tokens.update new_tokens
        @updating = false
      end

      (@active_gems | @pending_gems).each do |name|
        refresh_gem(name)
      end
    end

    true
  end

  def refresh_gem(gem_name, immediate = true)
    update

    already_active = nil
    @monitor.synchronize do
      if @updating && !@gem_tokens.key?(gem_name)
        @pending_gems << gem_name
        return
      end

      already_active = !@active_gems.add?(gem_name)
    end

    unless @gem_tokens.key?(gem_name)
      @monitor.synchronize do
        @gem_info[gem_name] = {}
        @refresh_cond.broadcast
        return
      end
    end

    error = lambda do |ex|
      @monitor.synchronize do
        @gem_info[gem_name] = ex
        @refresh_cond.broadcast
      end
    end

    pinboard.async_file(uri("info", gem_name), token: @gem_tokens[gem_name], only_updated: already_active, error: error) do |f|
      dependency_names = Set.new
      info = {}

      started = false
      f.each_line do |line|
        unless started
          started ||= line == "---\n"
          next
        end
        line.chop!

        version, rest = line.split(" ", 2)
        deps, attrs = rest.split("|", 2)

        deps = deps.split(",").map do |entry|
          key, constraints = entry.split(":", 2)
          constraints = constraints.split("&")
          [key, constraints]
        end

        attributes = { dependencies: deps }
        attrs.scan(/(\w+):((?:[^,]+|,(?!\w+:))*)/) do |key, value|
          attributes[key.to_sym] = value
        end

        deps.each do |name, _|
          dependency_names << name
        end

        info[version] = attributes
      end

      @monitor.synchronize do
        @gem_info[gem_name] = info
        @refresh_cond.broadcast
      end
    end
  end

  private

  def pinboard_dir
    File.expand_path("~/.cache/paperback/index/#{@uri_identifier}")
  end
end
