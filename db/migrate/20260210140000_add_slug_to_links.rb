# frozen_string_literal: true

class AddSlugToLinks < ActiveRecord::Migration[8.1]
  def up
    add_column :links, :slug, :string
    add_index :links, :slug, unique: true, where: 'slug IS NOT NULL'

    say_with_time 'backfill_link_slugs' do
      Link.find_each do |link|
        next if link.slug.present?

        link.update_column(:slug, Base62.encode(link.id))
      end
    end
  end

  def down
    remove_index :links, :slug
    remove_column :links, :slug
  end
end
