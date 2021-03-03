class CreateOmiaiTokens < ActiveRecord::Migration[6.1]
  def change
    create_table :omiai_tokens do |t|
      t.text :token

      t.timestamps
    end
  end
end
