# encoding: UTF-8

class PageViewSeen
  include Mongoid::Document

  # The frontend's name for it, which Mongoid's pluralised default wouldn't
  # find.
  store_in collection: "page_view_seen"

  field :slug, type: String
  # A String to match how the frontend writes it, so reads don't mis-cast.
  field :day, type: String
  field :ipHash, type: String, as: :ip_hash
  # Absent on markers written before the frontend recorded it.
  field :country, type: String
  field :at, type: Time, as: :seen_at

  validates :slug, :day, :ip_hash, presence: true
end
