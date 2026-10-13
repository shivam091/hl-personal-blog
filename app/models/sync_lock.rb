# encoding: UTF-8

# Two syncs of the same report running at once both find a row missing and
# both insert it, and the live database has no unique indexes to refuse the
# second. A lock document's _id is the lock's name, which MongoDB keeps
# unique on its own, so it holds across processes where a cache wouldn't.
class SyncLock
  include Mongoid::Document

  # Longer than any sync takes, so a lock left by a crashed process doesn't
  # block syncing for good.
  TTL = 30.minutes

  field :_id, type: String, overwrite: true
  field :expires_at, type: Time
  # Says whose lock it is, so a run that outlived TTL can't release the lock
  # a later run took over.
  field :token, type: String

  class << self
    # Gives up at once when the lock is held, so an overlapping sync is
    # skipped rather than queued behind the first.
    def hold(name)
      token = SecureRandom.uuid
      return false unless acquire(name, token)

      begin
        yield
        true
      ensure
        where(_id: name, token: token).delete_all
      end
    end

    private

    def acquire(name, token)
      where(_id: name, :expires_at.lt => Time.current).delete_all
      collection.insert_one(_id: name, token: token, expires_at: TTL.from_now)
      true
    rescue Mongo::Error::OperationFailure => e
      raise unless e.code == 11000 # duplicate key: someone else holds it

      false
    end
  end
end
