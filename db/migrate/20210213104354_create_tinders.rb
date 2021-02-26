class CreateTinders < ActiveRecord::Migration[6.1]
  def change
    create_table :tinders do |t|
      t.text :access_token
      t.timestamps
    end
  end
end
