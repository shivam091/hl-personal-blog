# encoding: UTF-8

# Kept, so an entry's report for an age goes out once however often, or
# however late, the job runs.
class LaunchReportDelivery
  include Mongoid::Document

  field :entry_url, type: String
  field :age, type: Integer
  field :sent_at, type: Time

  index({entry_url: 1, age: 1}, {unique: true})

  validates :entry_url, :age, presence: true

  class << self
    # Taken in one atomic upsert before sending, so two runs at once can't
    # both mail it. False when it was taken already.
    def claim(entry_url, age)
      # The key alone, since an upsert needs an operator and a claim holds
      # nothing more until it's sent.
      before = where(entry_url: entry_url, age: age).find_one_and_update(
        {"$setOnInsert" => {entry_url: entry_url, age: age}}, upsert: true, return_document: :before
      )
      before.nil?
    end

    # Given back when the mail fails, so the next run tries again.
    def release(entry_url, age)
      where(entry_url: entry_url, age: age, sent_at: nil).delete_all
    end

    def sent(entry_url, age)
      where(entry_url: entry_url, age: age).update_all(sent_at: Time.current)
    end
  end
end
