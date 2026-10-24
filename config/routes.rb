Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :file_types, only: [:index, :show, :create, :update, :destroy]
  resources :columns, only: [:index, :show, :create, :update, :destroy]
  resources :transform_maps, only: [:index, :show, :create, :update, :destroy]
  resources :validations, only: [:index, :show, :create, :update, :destroy] do
    post "bulk", on: :collection, action: :bulk_create
    patch "bulk", on: :collection, action: :bulk_update
  end
  resources :transformations, only: [:index, :show, :create, :update, :destroy] do
    post "bulk", on: :collection, action: :bulk_create
    patch "bulk", on: :collection, action: :bulk_update
  end
  resources :column_validators, only: :index
  resources :column_transformers, only: :index
  # Defines the root path route ("/")
  # root "posts#index"
end
