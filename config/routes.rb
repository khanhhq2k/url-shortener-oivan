Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get 'up' => 'rails/health#show', as: :rails_health_check

  post 'encode', to: 'short_links#encode'
  post 'decode', to: 'short_links#decode'
end
