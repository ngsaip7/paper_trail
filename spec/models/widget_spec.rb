require 'rails_helper'

describe Widget, :type => :model do
  describe '`be_versioned` matcher' do
    it { is_expected.to be_versioned }
  end

  let(:widget) { Widget.create! :name => 'Bob', :an_integer => 1 }

  describe '`have_a_version_with` matcher', :versioning => true do
    before do
      widget.update_attributes!(:name => 'Leonard', :an_integer => 1 )
      widget.update_attributes!(:name => 'Tom')
      widget.update_attributes!(:name => 'Bob')
    end

    it "is possible to do assertions on versions" do
       expect(widget).to have_a_version_with :name => 'Leonard', :an_integer => 1
       expect(widget).to have_a_version_with :an_integer => 1
       expect(widget).to have_a_version_with :name => 'Tom'
    end
  end

  describe "`versioning` option" do
    context :enabled, :versioning => true do
      it 'should enable versioning for models wrapped within a block' do
        expect(widget.versions.size).to eq(1)
      end
    end

    context '`disabled` (default)' do
      it 'should not enable versioning for models wrapped within a block not marked to used versioning' do
        expect(widget.versions.size).to eq(0)
      end
    end
  end

  describe "Callbacks", :versioning => true do
    describe :before_save do
      context ':on => :update' do
        before { widget.update_attributes!(:name => 'Foobar') }

        subject { widget.versions.last.reify }

        it "should reset the value for the timestamp attrs for update so that value gets updated properly" do
          expect { subject.save! }.to change(subject, :updated_at)
        end
      end
    end

    describe :after_create do
      let(:widget) { Widget.create!(:name => 'Foobar', :created_at => Time.now - 1.week) }

      it "corresponding version should use the widget's `updated_at`" do
        expect(widget.versions.last.created_at.to_i).to eq(widget.updated_at.to_i)
      end
    end

    describe :after_update do
      before { widget.update_attributes!(:name => 'Foobar', :updated_at => Time.now + 1.week) }

      subject { widget.versions.last.reify }

      it { expect(subject).not_to be_live }

      it "should clear the `versions_association_name` virtual attribute" do
        subject.save!
        expect(subject).to be_live
      end

      it "corresponding version should use the widget updated_at" do
        expect(widget.versions.last.created_at.to_i).to eq(widget.updated_at.to_i)
      end
    end

    describe :after_destroy do
      it "should create a version for that event" do
        expect { widget.destroy }.to change(widget.versions, :count).by(1)
      end

      it "should assign the version into the `versions_association_name`" do
        expect(widget.version).to be_nil
        widget.destroy
        expect(widget.version).not_to be_nil
        expect(widget.version).to eq(widget.versions.last)
      end
    end

    describe :after_rollback do
      let(:rolled_back_name) { 'Big Moo' }

      before do
        begin
          widget.transaction do
            widget.update_attributes!(:name => rolled_back_name)
            widget.update_attributes!(:name => Widget::EXCLUDED_NAME)
          end
        rescue ActiveRecord::RecordInvalid
          widget.reload
          widget.name = nil
          widget.save
        end
      end

      it 'does not create an event for changes that did not happen' do
        widget.versions.map(&:changeset).each do |changeset|
          expect(changeset.fetch('name', [])).to_not include(rolled_back_name)
        end
      end
    end
  end

  describe "Association", :versioning => true do
    describe "sort order" do
      it "should sort by the timestamp order from the `VersionConcern`" do
        expect(widget.versions.to_sql).to eq(
          widget.versions.reorder(PaperTrail::Version.timestamp_sort_order).to_sql)
      end
    end
  end

  describe "Methods" do
    describe "Instance", :versioning => true do
      describe '#paper_trail_originator' do
        it { is_expected.to respond_to(:paper_trail_originator) }

        describe "return value" do
          let(:orig_name) { Faker::Name.name }
          let(:new_name) { Faker::Name.name }
          before { PaperTrail.whodunnit = orig_name }

          context "accessed from live model instance" do
            specify { expect(widget).to be_live }

            it "should return the originator for the model at a given state" do
              expect(widget.paper_trail_originator).to eq(orig_name)
              widget.whodunnit(new_name) { |w| w.update_attributes(:name => 'Elizabeth') }
              expect(widget.paper_trail_originator).to eq(new_name)
            end
          end

          context "accessed from a reified model instance" do
            before do
              widget.update_attributes(:name => 'Andy')
              PaperTrail.whodunnit = new_name
              widget.update_attributes(:name => 'Elizabeth')
            end

            context "default behavior (no `options[:dup]` option passed in)" do
              let(:reified_widget) { widget.versions[1].reify }

              it "should return the appropriate originator" do
                expect(reified_widget.paper_trail_originator).to eq(orig_name)
              end

              it "should not create a new model instance" do
                expect(reified_widget).not_to be_new_record
              end
            end

            context "creating a new instance (`options[:dup] == true`)" do
              let(:reified_widget) { widget.versions[1].reify(:dup => true) }

              it "should return the appropriate originator" do
                expect(reified_widget.paper_trail_originator).to eq(orig_name)
              end

              it "should not create a new model instance" do
                expect(reified_widget).to be_new_record
              end
            end
          end
        end
      end

      describe "#originator" do
        subject { widget }

        it { is_expected.to respond_to(:originator) }

        it 'should set the invoke `paper_trail_originator`' do
          allow(::ActiveSupport::Deprecation).to receive(:warn)
          is_expected.to receive(:paper_trail_originator)
          subject.originator
        end

        it 'should display a deprecation warning' do
          expect(::ActiveSupport::Deprecation).to receive(:warn).
            with(/Use paper_trail_originator instead of originator/)
          subject.originator
        end
      end

      describe '#version_at' do
        it { is_expected.to respond_to(:version_at) }

        context "Timestamp argument is AFTER object has been destroyed" do
          before do
            widget.update_attribute(:name, 'foobar')
            widget.destroy
          end

          it "should return `nil`" do
            expect(widget.version_at(Time.now)).to be_nil
          end
        end
      end

      describe '#whodunnit' do
        it { is_expected.to respond_to(:whodunnit) }

        context "no block given" do
          it "should raise an error" do
            expect { widget.whodunnit('Ben') }.to raise_error(ArgumentError, 'expected to receive a block')
          end
        end

        context "block given" do
          let(:orig_name) { Faker::Name.name }
          let(:new_name) { Faker::Name.name }

          before do
            PaperTrail.whodunnit = orig_name
            expect(widget.versions.last.whodunnit).to eq(orig_name) # persist `widget`
          end

          it "should modify value of `PaperTrail.whodunnit` while executing the block" do
            widget.whodunnit(new_name) do
              expect(PaperTrail.whodunnit).to eq(new_name)
              widget.update_attributes(:name => 'Elizabeth')
            end
            expect(widget.versions.last.whodunnit).to eq(new_name)
          end

          it "should revert the value of `PaperTrail.whodunnit` to it's previous value after executing the block" do
            widget.whodunnit(new_name) { |w| w.update_attributes(:name => 'Elizabeth') }
            expect(PaperTrail.whodunnit).to eq(orig_name)
          end

          context "error within block" do
            it "should ensure that the whodunnit value still reverts to it's previous value" do
              expect { widget.whodunnit(new_name) { raise } }.to raise_error
              expect(PaperTrail.whodunnit).to eq(orig_name)
            end
          end
        end
      end

      describe '#touch_with_version' do
        it { is_expected.to respond_to(:touch_with_version) }

        it "creates a version" do
          count = widget.versions.size
          widget.touch_with_version
          expect(widget.versions.size).to eq(count + 1)
        end

        it "increments the `:updated_at` timestamp" do
          time_was = widget.updated_at
          widget.touch_with_version
          expect(widget.updated_at).to be > time_was
        end
      end

      describe '#trail_for' do
        it { is_expected.to respond_to(:trail_for) }

        describe "return value" do
          context "when called for an attribute that is not present for the model" do
            it "should raise an error" do
              expect{widget.trail_for(:not_an_attribute)}.to raise_error(RuntimeError)
            end
          end

          context "when called with an attribute of the model" do
            context "when the value for the attribute is updated" do
              before { widget.update_attributes(:name => 'Sam') }

              it "should contain an hash with the version id of the update event" do
                expect(widget.trail_for(:name).any? { |change| change["version_id"] == widget.versions.last.id }).to be_truthy
              end

              it "should contain the initial value before the change and the final value of the attribute after the change" do
                initial_value = widget.name
                final_value = "Ron"

                widget.update_attributes(:name => final_value)

                expect(widget.trail_for(:name).last["initial_value"]).to eq(initial_value)
                expect(widget.trail_for(:name).last["final_value"]).to eq(final_value)
              end

              it "should contain the timestamp when the change occurred" do
                expect(widget.trail_for(:name).last["changed_at"]).to eq(widget.versions.last.created_at)
              end

              it "should contain the user who was responsible for the change" do
                expect(widget.trail_for(:name).last["whodunnit"]).to eq(widget.versions.last.whodunnit)
              end

              it "should return a array of hashes in descending order of occurrence" do
                expect(widget.trail_for(:name).first["changed_at"]).to eq(widget.versions.creates.first.created_at)
                expect(widget.trail_for(:name).last["changed_at"]).to eq(widget.versions.last.created_at)
              end
            end

            context "when the value for some other attribute is updated" do
              it "should not contain an hash with the version id of the update event" do
                widget.update_attributes(:an_integer => 777)

                expect(widget.trail_for(:name).any? { |change| change["version_id"] == widget.versions.last.id }).to be_falsey
              end
            end

            context "when the value for the required attribute and another attribute is updated" do
              it "should contain an hash with the version id of the update event" do
                widget.update_attributes(:name => 'Harry', :an_integer => 1845)

                expect(widget.trail_for(:name).any? { |change| change["version_id"] == widget.versions.last.id }).to be_truthy
              end

              it "should return an hash with the initial value and the final value of the attribute after the change" do
                initial_value = widget.name
                final_value = "Red"

                widget.update_attributes(:name => final_value, :an_integer => 1732)

                expect(widget.trail_for(:name).last["initial_value"]).to eq(initial_value)
                expect(widget.trail_for(:name).last["final_value"]).to eq(final_value)
              end
            end
          end
        end
      end
    end

    describe "Class" do
      subject { Widget }

      describe "#paper_trail_enabled_for_model?" do
        it { is_expected.to respond_to(:paper_trail_enabled_for_model?) }

        it { expect(subject.paper_trail_enabled_for_model?).to be true }
      end

      describe '#paper_trail_off!' do
        it { is_expected.to respond_to(:paper_trail_off!) }

        it 'should set the `paper_trail_enabled_for_model?` to `false`' do
          expect(subject.paper_trail_enabled_for_model?).to be true
          subject.paper_trail_off!
          expect(subject.paper_trail_enabled_for_model?).to be false
        end
      end

      describe '#paper_trail_on!' do
        before { subject.paper_trail_off! }

        it { is_expected.to respond_to(:paper_trail_on!) }

        it 'should set the `paper_trail_enabled_for_model?` to `true`' do
          expect(subject.paper_trail_enabled_for_model?).to be false
          subject.paper_trail_on!
          expect(subject.paper_trail_enabled_for_model?).to be true
        end
      end
    end
  end
end
