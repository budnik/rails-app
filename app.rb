begin
  require "bundler/inline"
rescue LoadError => e
  $stderr.puts "Bundler version 1.10 or later is required. Please update your Bundler"
  raise e
end

gemfile(true) do
  source "https://rubygems.org"

  gem "rails"
  gem "pg"
  gem "factory_girl_rails"
end

require "active_record"
require "action_controller/railtie"

ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "railstestdb")
ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :books, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :categories, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :categorizations, force: true do |t|
    t.references :book
    t.references :category
    t.boolean :primary, default: false, null: false
    t.timestamps
  end
end

class Book < ActiveRecord::Base
  has_many :categorizations
  has_many :categories, through: :categorizations
end

class Category < ActiveRecord::Base
  has_many :categorizations
  has_many :books, through: :categorizations

  def self.primaries
    Category.joins(:categorizations).merge(Categorization.primaries)
  end
end

class Categorization < ActiveRecord::Base
  belongs_to :book
  belongs_to :category

  def self.primaries
    where(primary: true)
  end
end

class TestApp < Rails::Application
  secrets.secret_token    = "secret_token"
  secrets.secret_key_base = "secret_key_base"

  config.logger = Logger.new($stdout)
  Rails.logger = config.logger

  routes.draw do
    resources :primary_categories, only: :index
  end
end

class PrimaryCategoriesController < ActionController::Base
  include Rails.application.routes.url_helpers

  def index
    @primary_categories = Category.primaries
    render inline: "# of primary categories: <%= @primary_categories.count %>"
  end
end

FactoryGirl.define do
  factory :book do
    name "Thing Explainer: Complicated Stuff in Simple Words"

    trait :with_primary_category do
      after(:create) do |book, _|
        book.categorizations << Categorization.create!(category: create(:science_category), book: book, primary: true)
      end
    end

    trait :with_secondary_category do
      after(:create) do |book, _|
        book.categorizations << Categorization.create!(category: create(:fun_facts_category), book: book, primary: false)
      end
    end
  end

  factory :science_category, class: Category do
    name "Science & Scientists"
  end

  factory :fun_facts_category, class: Category do
    name "Trivia & Fun Facts"
  end
end

require "minitest/autorun"

class CategoryTest < Minitest::Test
  def test_primary_categories
    FactoryGirl.create(:book, :with_primary_category, :with_secondary_category)

    assert_equal [Category.find_by_name('Science & Scientists')], Category.primaries
  end
end

class PrimaryCategoriesTest < Minitest::Test
  include Rack::Test::Methods

  def test_index
    get "/primary_categories"

    assert last_response.ok?
    assert_equal "# of primary categories: 1", last_response.body
  end

  private

  def app
    Rails.application
  end
end
