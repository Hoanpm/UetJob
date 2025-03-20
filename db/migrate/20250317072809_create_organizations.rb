class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.text :description
      t.string :email_domain, null: false
      t.string :avatar

      t.timestamps
    end

    add_index :organizations, :email_domain, unique: true
  end
end
