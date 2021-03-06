require "rubygems"
require "nokogiri"

module GeoRuby
  module Gpx4r

    #An interface to GPX files
    class GpxFile
      attr_reader :record_count, :file_root #:xmin, :ymin, :xmax, :ymax, :zmin, :zmax, :mmin, :mmax, :file_length

      include Enumerable

      # Opens a GPX file. Both "abc.shp" and "abc" are accepted.
      def initialize(file, *opts) #with_z = true, with_m = true)
        @file_root = file.gsub(/\.gpx$/i,"")
        raise MalformedGpxException.new("Missing GPX File") unless
          File.exists? @file_root + ".gpx"
        @points, @envelope = [], nil
        @gpx = File.open(@file_root + ".gpx", "rb")
        opt = opts.inject({}) { |o, h| h.merge(o) }
        parse_file(opt[:with_z], opt[:with_m])
      end

      #force the reopening of the files compsing the shp. Close before calling this.
      def reload!
        initialize(@file_root)
      end

      #opens a GPX "file". If a block is given, the GpxFile object is yielded to it and is closed upon return. Else a call to <tt>open</tt> is equivalent to <tt>GpxFile.new(...)</tt>.
      def self.open(file, *opts)
        gpxfile = GpxFile.new(file, *opts)
        if block_given?
          yield gpxfile
          # gpxfile.close
        else
          gpxfile
        end
      end
      
      def self.write(attrs = {}, gpx_opts = {}, xml_opts = {})
        points        = attrs.delete(:points)
        line_strings  = attrs.delete(:line_strings)
        # polygons      = attrs.delete(:polygons)
        metadata      = attrs.delete(:metadata)
        
        builder = Nokogiri::XML::Builder.new(xml_opts) do |xml|
          xml.gpx(gpx_opts) {
            metadata_to_xml(metadata, xml) unless metadata.nil?
            points_to_xml(points, xml) unless points.nil?
            line_strings_to_xml(line_strings, xml) unless line_strings.nil?
          }
        end
        
        builder
      end

      #Closes a gpxfile
      def close
        @gpx.close
      end

      #Tests if the file has no record
      def empty?
        record_count == 0
      end

      #Goes through each record
      def each
        (0...record_count).each do |i|
          yield get_record(i)
        end
      end
      alias :each_record :each

      #Returns record +i+
      def [](i)
        get_record(i)
      end

      #Returns all the records
      def records
        @points
      end

      # Return the GPX file as LineString
      def as_line_string
        GeoRuby::SimpleFeatures::LineString.from_points(@points)
      end
      alias :as_polyline :as_line_string

      # Return the GPX file as a Polygon
      # If the GPX isn't closed, a line from the first
      # to the last point will be created to close it.
      def as_polygon
        GeoRuby::SimpleFeatures::Polygon.from_points([@points[0] == @points[-1] ?  @points : @points.push(@points[0].clone)])
      end

      # Return GPX Envelope
      def envelope
        @envelope ||= as_polygon.envelope
      end

      private

      def get_record(i)
        @points[i]
      end

      # wpt => waypoint => TODO?
      # rte(pt) => route
      # trk(pt) => track /
      def parse_file(with_z, with_m)
        data = @gpx.read
        @file_mode = data =~ /trkpt/ ? "//trkpt" : (data =~ /wpt/ ? "//wpt" : "//rtept")
        Nokogiri.HTML(data).search(@file_mode).each do |tp|
          z = z.inner_text.to_f if with_z && z = tp.at("ele")
          m = m.inner_text if with_m && m = tp.at("time")
          @points << GeoRuby::SimpleFeatures::Point.from_coordinates([tp["lon"].to_f, tp["lat"].to_f, z, m],4326,with_z, with_m)
        end
        close
        @record_count = @points.length
        self.envelope
      rescue => e
        raise MalformedGpxException.new("Bad GPX. Error: #{e}")
        # trackpoint.at("gpxdata:hr").nil? # heartrate
      end
      
      def self.metadata_to_xml(metadata, xml)
        xml.metadata {
          xml.name { xml.text(metadata.delete(:name)) } unless metadata[:name].nil?
          xml.desc { xml.text(metadata.delete(:desc)) } unless metadata[:desc].nil?
          xml.author { 
            xml.name { xml.text(metadata[:author][:name]) } unless metadata[:author][:name].nil?
            xml.link(:href => metadata[:author][:link]) unless metadata[:author][:link].nil?
          } unless metadata[:author].nil?
          xml.link { xml.text(metadata.delete(:link)) } unless metadata[:link].nil?
          xml.keywords { xml.text(metadata.delete(:keywords)) } unless metadata[:keywords].nil?
          xml.bounds { xml.text(metadata.delete(:bounds)) } unless metadata[:bounds].nil?
        }
      end
  
      def self.points_to_xml(points, xml, opts = {})
        tag     = opts.delete(:tag) || 'wpt'
        parent  = opts.delete(:parent) || nil
        
        with_z = parent.nil? ? true : parent.with_z?
        with_m = parent.nil? ? true : parent.with_m?
        
        points.each do |p|
          xml.send(tag, :lat => p.y, :lon => p.x) {
            xml.ele { xml.text(p.z) } if with_z && p.with_z?
            # xml.time { xml.text(p.m) } if with_m && p.with_m?
            xml.name { xml.text(p.ref.name) } unless p.ref.nil? || p.ref.name.nil?
            xml.desc { xml.text(p.ref.desc) } unless p.ref.nil? || p.ref.desc.nil?
          }
        end
      end
      
      def self.line_strings_to_xml(line_strings, xml)
        line_strings.each do |t|
          xml.trk {
            xml.name { xml.text(t.ref.name) } unless t.ref.nil? || t.ref.name.nil?
            xml.desc { xml.text(t.ref.desc) } unless t.ref.nil? || t.ref.desc.nil?
            xml.trkseg {
              points_to_xml(t.points, xml, { :tag => 'trkpt', :parent => t })
            }
          }
        end
      end

    end

    class MalformedGpxException < StandardError
    end

  end

end
