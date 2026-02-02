# frozen_string_literal: true

class Order < ApplicationRecord
  belongs_to :customer
end
