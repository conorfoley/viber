ExUnit.start(exclude: [:live])

if Viber.Runtime.SessionStore.available?() do
  ExUnit.configure(exclude: [:requires_no_repo, :live])
end
