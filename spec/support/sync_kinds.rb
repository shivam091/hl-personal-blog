# encoding: UTF-8

# Specs of the sync history must not depend on which pages register a
# sync, so they get two kinds of their own.
module SyncKindHelpers
  def stub_sync_kinds
    enqueued = []
    kinds = {
      "posts" => SyncRequest::Kind.new(
        key: "posts",
        section: "Blog posts",
        source: "Blog feed",
        page: :sync_requests_path,
        enqueue: ->(request) { enqueued << request }
      ),
      "pages" => SyncRequest::Kind.new(
        key: "pages",
        section: "Blog pages",
        source: "Blog sitemap",
        page: :sync_requests_path,
        enqueue: ->(request) { enqueued << request }
      )
    }
    stub_const("SyncRequest::KINDS", kinds.freeze)
    enqueued
  end
end

RSpec.configure { |config| config.include SyncKindHelpers }
