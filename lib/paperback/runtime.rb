if ENV["PAPERBACK_STORE"]
  # TODO: This loads too much
  require "paperback"

  store = Paperback::Store.new(ENV["PAPERBACK_STORE"])

  if ENV["PAPERBACK_LOCKFILE"]
    loader = Paperback::LockLoader.new(ENV["PAPERBACK_LOCKFILE"])

    loader.activate(Paperback::Environment, store)
  end
end