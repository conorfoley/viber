ExUnit.start(exclude: [:live, :slow])

if Viber.Runtime.SessionStore.available?() do
  ExUnit.configure(exclude: [:requires_no_repo, :live, :slow])
end
