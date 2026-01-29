# frozen_string_literal: true

require_relative "entry"

module TavernKit
  module Lore
    # Lorebook value object matching CCv2/CCv3 character_book shape.
    Book = Data.define(
      :name,
      :description,
      :scan_depth,
      :token_budget,
      :recursive_scanning,
      :extensions,
      :entries,
    ) do
      def initialize(
        name: nil,
        description: nil,
        scan_depth: nil,
        token_budget: nil,
        recursive_scanning: nil,
        extensions: nil,
        entries: []
      )
        if !name.nil? && !name.is_a?(String)
          raise ArgumentError, "name must be a String (or nil), got: #{name.class}"
        end

        if !description.nil? && !description.is_a?(String)
          raise ArgumentError, "description must be a String (or nil), got: #{description.class}"
        end

        if !scan_depth.nil? && !scan_depth.is_a?(Integer)
          raise ArgumentError, "scan_depth must be an Integer (or nil), got: #{scan_depth.class}"
        end

        if !token_budget.nil? && !token_budget.is_a?(Integer)
          raise ArgumentError, "token_budget must be an Integer (or nil), got: #{token_budget.class}"
        end

        if !recursive_scanning.nil? && recursive_scanning != true && recursive_scanning != false
          raise ArgumentError, "recursive_scanning must be a Boolean (or nil), got: #{recursive_scanning.class}"
        end

        if !extensions.nil? && !extensions.is_a?(Hash)
          raise ArgumentError, "extensions must be a Hash (or nil), got: #{extensions.class}"
        end
        extensions = (extensions || {}).transform_keys(&:to_s).dup.freeze

        entries = Array(entries).map do |e|
          e.is_a?(Entry) ? e : Entry.from_h(e)
        end

        super(
          name: name,
          description: description,
          scan_depth: scan_depth,
          token_budget: token_budget,
          recursive_scanning: recursive_scanning,
          extensions: extensions,
          entries: entries.freeze,
        )
      end

      def recursive_scanning? = recursive_scanning == true

      def enabled_entries
        entries.select(&:enabled?)
      end

      def constant_entries
        entries.select(&:constant?)
      end

      def empty?
        entries.empty?
      end

      def entry_count = entries.size

      def to_h
        h = {
          "entries" => entries.map(&:to_h),
          "extensions" => extensions,
        }
        h["name"] = name unless name.nil?
        h["description"] = description unless description.nil?
        h["scan_depth"] = scan_depth unless scan_depth.nil?
        h["token_budget"] = token_budget unless token_budget.nil?
        h["recursive_scanning"] = recursive_scanning unless recursive_scanning.nil?
        h
      end

      def self.from_h(hash)
        raise ArgumentError, "Book must be a Hash" unless hash.is_a?(Hash)

        h = hash.transform_keys(&:to_s)
        new(
          name: h["name"],
          description: h["description"],
          scan_depth: h.key?("scan_depth") ? (h["scan_depth"]&.to_i) : nil,
          token_budget: h.key?("token_budget") ? (h["token_budget"]&.to_i) : nil,
          recursive_scanning: h.key?("recursive_scanning") ? h["recursive_scanning"] : nil,
          extensions: h["extensions"],
          entries: h["entries"] || [],
        )
      end
    end
  end
end
