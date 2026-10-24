Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :file_types, only: [:index, :show, :create, :update, :destroy]
  patch "file_types/:file_type_id/columns", to: "columns#bulk_modify"
  patch "file_types/:file_type_id/validations", to: "validations#bulk_modify"
  resources :columns, only: [:index, :show, :create, :update, :destroy]
  resources :transform_maps, only: [:index, :show, :create, :update, :destroy]
  patch "transform_maps/:transform_map_id/transformations", to: "transformations#bulk_modify"
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
