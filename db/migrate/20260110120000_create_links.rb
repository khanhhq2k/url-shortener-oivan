# frozen_string_literal: true

class CreateLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :links do |t|
      t.text :original_url, null: false
      t.timestamps
    end

    add_index :links, :original_url, unique: true
  end
end
