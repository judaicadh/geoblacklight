module Geoblacklight
  class SearchBuilder < Blacklight::Solr::SearchBuilder
    self.default_processor_chain += [:add_spatial_params]

    def initialize(processor_chain, scope)
      super(processor_chain, scope)
      @processor_chain += geoblacklight_search_methods
    end
    
    ##
    # List of request processing methods used in GeoBlacklight
    # to generate Solr query parameters.
    # @return Array
    def geoblacklight_search_methods
      [:add_spatial_params, :hide_child_resources, :show_child_resources]
    end

    ##
    # Adds spatial parameters to a Solr query if :bbox is present.
    # @param [Blacklight::Solr::Request] solr_params :bbox should be in Solr
    # :bbox should be passed in using Solr lat-lon rectangle format e.g.
    # "minX minY maxX maxY"
    # @return [Blacklight::Solr::Request]
    def add_spatial_params(solr_params)
      if blacklight_params[:bbox]
        solr_params[:bq] ||= []
        solr_params[:bq] = ["#{Settings.GEOMETRY_FIELD}:\"IsWithin(#{envelope_bounds})\"^10"]
        solr_params[:fq] ||= []
        solr_params[:fq] << "#{Settings.GEOMETRY_FIELD}:\"Intersects(#{envelope_bounds})\""
      end
      solr_params
    rescue Geoblacklight::Exceptions::WrongBoundingBoxFormat
      # TODO: Potentially delete bbox params here so that its not rendered as search param
      solr_params
    end

    ##
    # @return [String]
    def envelope_bounds
      bounding_box.to_envelope
    end

    ##
    # Returns a Geoblacklight::BoundingBox built from the blacklight_params
    # @return [Geoblacklight::BoundingBox]
    def bounding_box
      Geoblacklight::BoundingBox.from_rectangle(blacklight_params[:bbox])
    end

    ## 
    # Adds parameter to the Solr query that supresses objects that
    # are children of Colletion objects. There is no supression
    # during show actions and when the user facets on a collection.
    # @param [Blacklight::Solr::Request]
    # @return [Blacklight::Solr::Request]
    def hide_child_resources(solr_params)
      return if show_action? || parent_search
      solr_params[:fq] ||= []
      solr_params[:fq] << "!dct_isPartOf_sm:['' TO *]"
    end

    ## 
    # Appends a dc_identifier query with an OR to a dct_isPartOf facet query.
    # This allows the parent record in a collection to appear in a 
    # list with it's children. Does not occur during show actions. Results are sorted
    # by type so that the collection record appears at the top of the list.
    # @param [Blacklight::Solr::Request]
    # @return [Blacklight::Solr::Request]
    def show_child_resources(solr_params)
      return if show_action? || !parent_search
      query = "dct_isPartOf_sm:#{parent_search[0]} " \
              "OR dc_identifier_s:#{parent_search[0]}"
      solr_params[:fq].map!{ |i| i[/^*.isPartOf.*$/] ? query : i }
      solr_params[:sort].prepend "dc_type_s asc, "
    end

    ##
    # Array of symbols for 'show' actions.
    # @return Array
    def self.show_actions
      [:show]
    end

    ##
    # Tests if current action param is a show action.
    # @return Boolean
    def show_action?
      self.class.show_actions.include? blacklight_params["action"].to_sym
    end

    ##
    # Return value of dct_isPartOf_sm facet request parameter.
    # @return Array
    def parent_search
      blacklight_params["f"] && blacklight_params["f"]["dct_isPartOf_sm"]
    end
  end
end
