# encoding: UTF-8

class PageLikeSeen
  include Mongoid::Document

  # The frontend's name for it, which Mongoid's pluralised default wouldn't
  # find.
  store_in collection: "page_like_seen"

  field :slug, type: String
  # camelCase because these are the frontend's own keys in the shared live database.
  field :ipHash, type: String, as: :ip_hash
  field :country, type: String
  field :at, type: Time, as: :seen_at

  validates :slug, :ip_hash, presence: true
end
