require 'rails_helper'

describe ContentItem, :type => :model do
  describe "validations" do
    before :each do
      @item = build(:content_item)
    end

    context "#base_path" do
      it "should be required" do
        @item.base_path = nil
        expect(@item).not_to be_valid
        expect(@item.errors[:base_path].size).to eq(1)

        @item.base_path = ''
        expect(@item).not_to be_valid
        expect(@item.errors[:base_path].size).to eq(1)
      end

      it "should be an absolute path" do
        @item.base_path = 'invalid//absolute/path/'
        expect(@item).to_not be_valid
        expect(@item.errors[:base_path].size).to eq(1)
      end

      it "should have a db level uniqueness constraint" do
        item = create(:content_item, :base_path => "/foo")

        @item.base_path = "/foo"
        expect {
          @item.save! :validate => false
        }.to raise_error(Moped::Errors::OperationFailure)
      end
    end

    it "requires publishing_app to be set" do
      @item.publishing_app = ''
      expect(@item).not_to be_valid
      expect(@item.errors[:publishing_app].size).to eq(1)
    end

    context 'content_id' do
      # The fact that the content ID is optional is implicit in the factory

      it "accepts a UUID" do
        @item.content_id = "a7c48dac-f1c6-45a8-b5c1-5c407d45826f"
        expect(@item).to be_valid
      end

      it "does not accept an arbitrary string" do
        @item.content_id = "bacon"
        expect(@item).not_to be_valid
      end

      it "does not accept an empty string" do
        @item.content_id = ""
        expect(@item).not_to be_valid
      end
    end

    context 'links' do
      # We expect links to be hashes of type `{String => [UUID]}`. For example:
      #
      # {
      #   "related" => [
      #     "8242a29f-8ad1-4fbe-9f71-f9e57ea5f1ea",
      #     "9f99d6d0-8f3b-4ad1-aac0-4811be80de47"
      #   ]
      # }
      #
      # Mongoid will reject anything that isn't a Hash with an error, so we
      # needn't test those cases for now

      it 'allows hashes from strings to lists' do
        @item.links = {"related" => [SecureRandom.uuid]}
        expect(@item).to be_valid
      end

      it 'allows an empty list of content IDs' do
        @item.links = {"related" => []}
        expect(@item).to be_valid
      end

      describe "validating keys" do
        it 'rejects non-string keys' do
          @item.links = {12 => []}
          expect(@item).not_to be_valid
          expect(@item.errors[:links]).to eq(["Invalid link types: 12"])

          @item.links = {nil => []}
          expect(@item).not_to be_valid
          expect(@item.errors[:links]).to eq(["Invalid link types: "])
        end

        it "allows string keys that are underscored alphanumeric" do
          [
            'word',
            'word2word',
            'word_word',
          ].each do |key|
            @item.links = {key => []}
            expect(@item).to be_valid, "expected item to be valid with links key '#{key}'"
          end
        end

        it "rejects keys keys with non-allowed characters" do
          [
            'Uppercase',
            'space space',
            'dash-ed',
            'punctuation!',
            '',
          ].each do |key|
            @item.links = {key => []}
            expect(@item).not_to be_valid, "expected item not to be valid with links key '#{key}'"
            expect(@item.errors[:links]).to eq(["Invalid link types: #{key}"])
          end
        end
      end

      describe "validating values" do
        it 'rejects non-list values' do
          @item.links = {"related" => SecureRandom.uuid}
          expect(@item).not_to be_valid
          expect(@item.errors[:links]).to eq(["must map to lists of UUIDs"])
        end

        it 'rejects non-UUID content IDs' do
          @item.links = {"related" => [SecureRandom.uuid, "/vat-rates"]}
          expect(@item).not_to be_valid
          expect(@item.errors[:links]).to eq(["must map to lists of UUIDs"])
        end
      end
    end

    context 'update_type' do
      # update_type is not persisted, so should only be validated
      # on edit.  Otherwise items loaded from the db will be invalid

      it "is required when changing a content item" do
        @item.update_type = ''
        expect(@item).not_to be_valid
        expect(@item.errors[:update_type].size).to eq(1)
      end

      it "is not required for an item loaded from the db" do
        @item.save!

        item = ContentItem.find(@item.base_path)
        expect(item.update_type).to be_nil
        expect(item).to be_valid
      end
    end

    context 'fields used in message queue routing key' do
      [
        "format",
        "update_type",
      ].each do |field|
        it "requires #{field} to be suitable as a routing_key" do
          %w(
            word
            alpha12numeric
            under_score
            dashed-item
            mixedCASE
          ).each do |value|
            @item.public_send("#{field}=", value)
            expect(@item).to be_valid
          end

          [
            'no spaces',
            'puncutation!',
          ].each do |value|
            @item.public_send("#{field}=", value)
            expect(@item).not_to be_valid
            expect(@item.errors[field].size).to eq(1)
          end
        end
      end
    end

    context 'with a route that is not below the base path' do
      before do
        @item.routes= [
          { 'path' => @item.base_path, 'type' => 'exact' },
          { 'path' => '/wrong-path', 'type' => 'exact' },
        ]
      end

      it 'should be invalid' do
        expect(@item).to_not be_valid
        expect(@item.errors[:routes]).to eq(["must be below the base path"])
      end
    end

    context 'with an invalid type of route' do
      before do
        @item.routes= [ { 'path' => @item.base_path, 'type' => 'unsupported' } ]
      end

      it 'should be invalid' do
        expect(@item).to_not be_valid
        expect(@item.errors[:routes]).to eq(["are invalid"])
      end
    end

    context 'special cases for a redirect item' do
      before :each do
        @item.format = "redirect"
        @item.routes = []
        @item.redirects = [{"path" => @item.base_path, "type" => "exact", "destination" => "/somewhere"}]
      end

      it "should not require a title" do
        @item.title = nil
        expect(@item).to be_valid
      end

      it "should not require a rendering_app" do
        @item.rendering_app = nil
        expect(@item).to be_valid
      end

      it "should be invalid with an invalid redirect" do
        @item.redirects.first['type'] = "fooey"
        expect(@item).not_to be_valid
        expect(@item.errors[:redirects]).to eq(["are invalid"])
      end

      it "should be invalid if given any routes" do
        @item.routes = [{"path" => @item.base_path, "type" => "exact" }]
        expect(@item).not_to be_valid
        expect(@item.errors[:routes]).to eq(["redirect items cannot have routes"])
      end
    end
  end

  it "should set updated_at on upsert" do
    item = build(:content_item)
    Timecop.freeze do
      item.upsert
      item.reload

      expect(item.updated_at.to_s).to eq(Time.zone.now.to_s)
    end
  end

  it "should not persist update_type" do
    item = build(:content_item)
    item.update_attributes!(:update_type => "minor")

    expect(item.update_type).to eq("minor")

    item = ContentItem.find(item.base_path)
    expect(item.update_type).to be_nil
  end

  describe "registering routes" do
    before do
      routes = [
        { 'path' => '/a-path', 'type' => 'exact' },
        { 'path' => '/a-path.json', 'type' => 'exact' },
        { 'path' => '/a-path/subpath', 'type' => 'prefix' }
      ]

      @item = build(:content_item, base_path: '/a-path', rendering_app: 'an-app', routes: routes)
    end

    it 'registers the assigned routes when created' do
      @item.save!
      assert_routes_registered('an-app', [
        ['/a-path', 'exact'],
        ['/a-path.json', 'exact'],
        ['/a-path/subpath', 'prefix']
      ])
    end

    it 'registers the assigned routes when upserted' do
      @item.upsert
      assert_routes_registered('an-app', [
        ['/a-path', 'exact'],
        ['/a-path.json', 'exact'],
        ['/a-path/subpath', 'prefix']
      ])
    end
  end

  context 'when loaded from the content store' do
    before do
      create(:content_item, base_path: '/base_path', routes: [{ 'path' => '/base_path', 'type' => 'exact' }])
      @item = ContentItem.last
    end

    it "should be valid" do
      expect(@item).to be_valid
    end
  end

  describe '#linked_items' do

    context 'with no link types' do
      before :each do
        @item = build(:content_item)
      end

      it 'should return an empty hash' do
        expect(@item.linked_items).to eq({})
      end
    end

    context 'with an empty link type' do
      before :each do
        @item = build(:content_item)
        @item.links = {"related" => []}
      end

      it 'should include the key' do
        expect(@item.linked_items.keys).to eq(["related"])
      end

      it 'should have an empty list' do
        expect(@item.linked_items["related"]).to eq([])
      end
    end

    context 'with a published linked item' do
      before :each do
        @linked_item = create(:content_item, :with_content_id)
        @item = build(:content_item)
        @item.links = {"related" => [@linked_item.content_id]}
      end

      it 'should include the key' do
        expect(@item.linked_items.keys).to eq(["related"])
      end

      it 'should include the linked item' do
        expect(@item.linked_items["related"]).to eq([@linked_item])
      end
    end

    context 'with an unpublished linked item' do
      before :each do
        @item = build(
          :content_item,
          :links => {"related" => [SecureRandom.uuid]}
        )
      end

      it 'should not include the item' do
        expect(@item.linked_items["related"]).to eq([])
      end
    end

    context 'with a published item and redirects' do
      before :each do
        shared_content_id = SecureRandom.uuid

        # Creating two redirects, one before and one after the content item, so
        # we don't accidentally pass this test by taking the first or last item
        create(
          :redirect_content_item,
          :base_path => '/a',
          :content_id => shared_content_id
        )
        @linked_item = create(
          :content_item,
          :base_path => '/b',
          :content_id => shared_content_id
        )
        create(
          :redirect_content_item,
          :base_path => '/c',
          :content_id => shared_content_id
        )
        @item = build(
          :content_item,
          :links => {"related" => [shared_content_id]}
        )
      end

      it 'links to the content item' do
        expect(@item.linked_items["related"]).to eq([@linked_item])
      end
    end

    context 'with multiple published items' do
      before :each do
        shared_content_id = SecureRandom.uuid
        Timecop.travel(-10.seconds) do
          create(:content_item, :base_path => '/a', :content_id => shared_content_id)
          create(:content_item, :base_path => '/c', :content_id => shared_content_id)
        end
        @newer_linked_item = create(
          :content_item,
          :base_path => '/b',
          :content_id => shared_content_id
        )

        @item = build(
          :content_item,
          :links => {"related" => [shared_content_id]}
        )
      end

      it 'takes the most recent' do
        expect(@item.linked_items["related"]).to eq([@newer_linked_item])
      end
    end
  end
end