CLASS zcl_zabap_toc_ui5 DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES z2ui5_if_app.

    "! Selection-screen state.
    TYPES:
      BEGIN OF ts_sel,
        target_system    TYPE ko013-tarsystem,
        transport        TYPE trkorr,
        owner            TYPE tr_as4user,
        description      TYPE as4text,
        include_released TYPE abap_bool,
        include_tocs     TYPE abap_bool,
        include_subs     TYPE abap_bool,
        desc_mode        TYPE string,      " '0'=ToC-style '1'=Original '2'=Custom (popup)
        ignore_version   TYPE abap_bool,
        max_wait_sec     TYPE i,
      END OF ts_sel.

    "! One result row in the UI table.
    TYPES:
      BEGIN OF ts_row,
        released_text  TYPE string,
        main_transport TYPE trkorr,
        transport      TYPE trkorr,
        type           TYPE trfunction,
        target_system  TYPE tr_target,
        owner          TYPE tr_as4user,
        creation_date  TYPE as4date,
        description    TYPE as4text,
        toc_number     TYPE trkorr,
        toc_status     TYPE string,
        highlight      TYPE string,         " None | Success | Warning | Error | Information
      END OF ts_row.
    TYPES tt_row TYPE STANDARD TABLE OF ts_row WITH EMPTY KEY.

    "! Visible state - bound to the view via _bind / _bind_edit.
    DATA s_sel       TYPE ts_sel.
    DATA t_report    TYPE tt_row.

    "! State for the "custom description" popup flow.
    DATA pending_action       TYPE string.
    DATA pending_transport    TYPE trkorr.
    DATA custom_description   TYPE string.

  PROTECTED SECTION.

    DATA client TYPE REF TO z2ui5_if_client.

    METHODS on_init.
    METHODS on_event.

    METHODS view_main.
    METHODS popup_description.

    METHODS gather_transports.

    METHODS execute_action
      IMPORTING action      TYPE string
                row         TYPE REF TO ts_row
                description TYPE string OPTIONAL.

    METHODS new_engine
      IMPORTING desc_mode     TYPE i
      RETURNING VALUE(engine) TYPE REF TO zcl_zabap_toc.

  PRIVATE SECTION.

ENDCLASS.



CLASS zcl_zabap_toc_ui5 IMPLEMENTATION.

  METHOD z2ui5_if_app~main.
    me->client = client.
    IF client->check_on_init( ).
      on_init( ).
    ELSEIF client->check_on_event( ).
      on_event( ).
    ENDIF.
  ENDMETHOD.


  METHOD on_init.
    " Defaults that mirror the original report's selection screen.
    s_sel = VALUE #(
      owner            = sy-uname
      max_wait_sec     = 30
      ignore_version   = abap_true
      desc_mode        = `0`
      include_released = abap_false
      include_tocs     = abap_false
      include_subs     = abap_false ).
    view_main( ).
  ENDMETHOD.


  METHOD on_event.

    DATA(event) = client->get( )-event.
    DATA lr_row     TYPE REF TO ts_row.
    DATA lv_trkorr  TYPE trkorr.

    CASE event.

      WHEN `SEARCH`.
        gather_transports( ).
        IF t_report IS INITIAL.
          client->message_toast_display( `No transports match the selection.` ).
        ENDIF.

      WHEN `RESET`.
        t_report = VALUE #( ).
        client->message_toast_display( `Cleared.` ).

      WHEN `TOC_C` OR `TOC_CR` OR `TOC_CRI`.
        " event_arg(1) carries the transport number of the clicked row
        lv_trkorr = client->get_event_arg( 1 ).
        READ TABLE t_report WITH KEY transport = lv_trkorr REFERENCE INTO lr_row.
        IF sy-subrc <> 0.
          client->message_toast_display( `Row not found.` ).
          RETURN.
        ENDIF.

        IF s_sel-desc_mode = `2`. " custom
          " Custom description: capture text via popup, then continue.
          pending_action     = event.
          pending_transport  = lv_trkorr.
          custom_description = CONV string( lr_row->description ).
          popup_description( ).
          RETURN.
        ENDIF.

        execute_action( action = event row = lr_row ).

      WHEN `DESC_OK`.
        client->popup_destroy( ).
        READ TABLE t_report WITH KEY transport = pending_transport REFERENCE INTO lr_row.
        IF sy-subrc = 0.
          execute_action(
            action      = pending_action
            row         = lr_row
            description = custom_description ).
        ENDIF.
        CLEAR: pending_action, pending_transport, custom_description.

      WHEN `DESC_CANCEL`.
        client->popup_destroy( ).
        CLEAR: pending_action, pending_transport, custom_description.

      WHEN OTHERS.
        " ignore
    ENDCASE.

    view_main( ).

  ENDMETHOD.


  METHOD gather_transports.

    DATA lt_report TYPE tt_row.

    " Equivalent to ZCL_ZABAP_TOC_REPORT->gather_transports, but with single-value
    " filters (no SELECT-OPTIONS) - 'description' is matched with LIKE so '*' wildcards work.
    DATA(lv_descr_pattern) = COND as4text(
      WHEN s_sel-description IS INITIAL THEN '%'
      ELSE replace( val = s_sel-description sub = '*' with = '%' occ = 0 ) ).

    SELECT FROM e070
                LEFT JOIN e07t ON e07t~trkorr = e070~trkorr
                LEFT JOIN e070 AS sup ON sup~trkorr = e070~strkorr
      FIELDS
        CASE WHEN e070~trstatus = 'L' OR e070~trstatus = 'D' THEN @space
             ELSE 'X' END AS released_flag,
        CASE WHEN sup~trkorr IS NULL THEN e070~trkorr ELSE sup~trkorr END AS main_transport,
        e070~trkorr        AS transport,
        e070~trfunction    AS type,
        CASE WHEN e070~tarsystem <> @space THEN e070~tarsystem ELSE sup~tarsystem END AS target_system,
        e070~as4user       AS owner,
        e070~as4date       AS creation_date,
        e07t~as4text       AS description
      WHERE ( @s_sel-transport = @space OR e070~trkorr  = @s_sel-transport )
        AND ( @s_sel-owner     = @space OR e070~as4user = @s_sel-owner     )
        AND ( @s_sel-description = @space OR e07t~as4text LIKE @lv_descr_pattern )
        AND ( @s_sel-include_subs     = @abap_true OR e070~strkorr = @space )
        AND ( @s_sel-include_released = @abap_true
              OR e070~trstatus IN ( 'L', 'D' )
              OR sup~trstatus  IN ( 'L', 'D' ) )
        AND ( @s_sel-include_tocs     = @abap_true OR e070~trfunction <> 'T' )
      ORDER BY e070~trkorr DESCENDING, e070~as4date DESCENDING
      INTO TABLE @DATA(lt_raw).

    " Build display rows
    LOOP AT lt_raw REFERENCE INTO DATA(lr_raw).
      DATA(ls_row) = VALUE ts_row(
        main_transport = lr_raw->main_transport
        transport      = lr_raw->transport
        type           = lr_raw->type
        target_system  = lr_raw->target_system
        owner          = lr_raw->owner
        creation_date  = lr_raw->creation_date
        description    = lr_raw->description
        released_text  = COND #( WHEN lr_raw->released_flag = 'X' THEN 'Released' ELSE 'Open' )
        highlight      = `None` ).
      APPEND ls_row TO lt_report.
    ENDLOOP.

    " Deduplicate by transport (same as the original)
    SORT lt_report BY transport.
    DELETE ADJACENT DUPLICATES FROM lt_report COMPARING transport.
    SORT lt_report BY creation_date DESCENDING transport DESCENDING.

    t_report = lt_report.

  ENDMETHOD.


  METHOD execute_action.

    DATA(target_system) = COND tr_target(
      WHEN s_sel-target_system IS INITIAL THEN row->target_system
      ELSE s_sel-target_system ).

    " For "custom" description we feed the engine the user-typed text and use the
    " "original" strategy, which means the engine just passes the description through.
    DATA(lv_desc_mode_int) = CONV i( s_sel-desc_mode ).
    DATA(desc_mode_eff) = COND i(
      WHEN lv_desc_mode_int = zcl_zabap_toc_description=>c_toc_description-custom
        THEN zcl_zabap_toc_description=>c_toc_description-original
      ELSE lv_desc_mode_int ).

    DATA(engine) = new_engine( desc_mode_eff ).

    DATA(source_description) = COND string(
      WHEN description IS NOT INITIAL THEN description
      ELSE CONV string( row->description ) ).

    CLEAR row->highlight.

    TRY.
        CASE action.

          WHEN `TOC_C`.
            row->toc_number = engine->create(
              source_transport   = row->transport
              source_description = source_description
              target_system      = target_system ).
            row->toc_status = `Created`.
            row->highlight  = `Success`.

          WHEN `TOC_CR`.
            row->toc_number = engine->create(
              source_transport   = row->transport
              source_description = source_description
              target_system      = target_system ).
            engine->release( row->toc_number ).
            row->toc_status = `Created + Released`.
            row->highlight  = `Success`.

          WHEN `TOC_CRI`.
            row->toc_number = engine->create(
              source_transport   = row->transport
              source_description = source_description
              target_system      = target_system ).
            engine->release( row->toc_number ).
            DATA(rc) = CONV i( engine->import(
              toc                  = row->toc_number
              target_system        = target_system
              max_wait_time_in_sec = s_sel-max_wait_sec
              ignore_version       = s_sel-ignore_version ) ).
            row->toc_status = |Imported (rc={ rc })|.
            row->highlight  = COND #( WHEN rc = 0 THEN `Success`
                                      WHEN rc = 4 THEN `Warning`
                                      ELSE             `Error` ).
        ENDCASE.

      CATCH zcx_zabap_user_cancel.
        row->toc_status = `Cancelled`.
        row->highlight  = `Error`.

      CATCH zcx_zabap_exception INTO DATA(lx).
        row->toc_status = lx->get_text( ).
        row->highlight  = `Error`.

      CATCH cx_root INTO DATA(lx_root).
        row->toc_status = lx_root->get_text( ).
        row->highlight  = `Error`.
    ENDTRY.

    client->message_toast_display( |{ row->transport }: { row->toc_status }| ).

  ENDMETHOD.


  METHOD new_engine.
    DATA(desc) = NEW zcl_zabap_toc_description( desc_mode ).
    engine = NEW zcl_zabap_toc( desc ).
  ENDMETHOD.


  METHOD view_main.

    DATA(view) = z2ui5_cl_xml_view=>factory( ).
    DATA(page) = view->shell( )->page(
      title         = `abap2UI5 - Transport of Copies`
      shownavbutton = abap_false ).

    " ---------- Selection block ----------
    DATA(form) = page->grid( `L8 M10 S12` )->content( `layout`
        )->simple_form( title = `Selection` editable = abap_true )->content( `form` ).

    form->title( `Target System` ).
    form->label( `Target System / Group`
        )->input(
            value       = client->_bind_edit( s_sel-target_system )
            placeholder = `e.g. Q01 or /MY_GRP/` ).

    form->title( `Filters` ).
    form->label( `Transport`
        )->input(
            value       = client->_bind_edit( s_sel-transport )
            placeholder = `single TR number, blank = all` ).

    form->label( `Owner`
        )->input(
            value       = client->_bind_edit( s_sel-owner )
            placeholder = `user name, blank = all` ).

    form->label( `Description (LIKE, * wildcard)`
        )->input(
            value       = client->_bind_edit( s_sel-description )
            placeholder = `*foo*` ).

    form->label( `Include released transports`
        )->checkbox( selected = client->_bind_edit( s_sel-include_released ) ).

    form->label( `Include ToCs`
        )->checkbox( selected = client->_bind_edit( s_sel-include_tocs ) ).

    form->label( `Include subtransports`
        )->checkbox( selected = client->_bind_edit( s_sel-include_subs ) ).

    form->title( `Options` ).
    form->label( `Description style`
        )->segmented_button( selected_key = client->_bind_edit( s_sel-desc_mode )
            )->items(
                )->segmented_button_item( key = `0` text = `ToC-style`
                )->segmented_button_item( key = `1` text = `Original`
                )->segmented_button_item( key = `2` text = `Custom (popup)` ).

    form->label( `Max wait time on import (sec)`
        )->input(
            value = client->_bind_edit( s_sel-max_wait_sec )
            type  = `Number` ).

    form->label( `Ignore version on import`
        )->checkbox( selected = client->_bind_edit( s_sel-ignore_version ) ).

    " ---------- Action toolbar (search/reset) ----------
    page->footer(
        )->overflow_toolbar(
            )->toolbar_spacer(
            )->button(
                text  = `Reset`
                press = client->_event( `RESET` )
                icon  = `sap-icon://clear-all`
            )->button(
                text  = `Search`
                press = client->_event( `SEARCH` )
                type  = `Emphasized`
                icon  = `sap-icon://search` ).

    " ---------- Result table ----------
    DATA(tab) = page->table(
      headertext = `Transports`
      growing    = abap_true
      growingthreshold = `100`
      mode       = `None`
      items      = client->_bind( t_report ) ).

    tab->columns(
        )->column( width = `6rem`  )->text( `Status` )->get_parent(
        )->column( width = `9rem`  )->text( `Transport` )->get_parent(
        )->column( width = `4rem`  )->text( `Type` )->get_parent(
        )->column( width = `8rem`  )->text( `Target` )->get_parent(
        )->column( width = `8rem`  )->text( `Owner` )->get_parent(
        )->column( width = `7rem`  )->text( `Created` )->get_parent(
        )->column( width = `20rem` )->text( `Description` )->get_parent(
        )->column( width = `4rem` halign = `Center` )->text( `ToC` )->get_parent(
        )->column( width = `4rem` halign = `Center` )->text( `+Rel` )->get_parent(
        )->column( width = `4rem` halign = `Center` )->text( `+Imp` )->get_parent(
        )->column( width = `9rem`  )->text( `New ToC` )->get_parent(
        )->column( width = `15rem` )->text( `Result` )->get_parent( ).

    DATA(cells) = tab->items( )->column_list_item( highlight = `{HIGHLIGHT}` )->cells( ).
    cells->text( `{RELEASED_TEXT}` ).
    cells->text( `{TRANSPORT}` ).
    cells->text( `{TYPE}` ).
    cells->text( `{TARGET_SYSTEM}` ).
    cells->text( `{OWNER}` ).
    cells->text( `{CREATION_DATE}` ).
    cells->text( `{DESCRIPTION}` ).

    " Three icon buttons replacing the SALV hotspot columns
    cells->button(
      icon    = `sap-icon://create`
      tooltip = `Create ToC`
      type    = `Transparent`
      press   = client->_event( val = `TOC_C`
                                 t_arg = VALUE #( ( `${TRANSPORT}` ) ) ) ).
    cells->button(
      icon    = `sap-icon://activate`
      tooltip = `Create + Release ToC`
      type    = `Transparent`
      press   = client->_event( val = `TOC_CR`
                                 t_arg = VALUE #( ( `${TRANSPORT}` ) ) ) ).
    cells->button(
      icon    = `sap-icon://process`
      tooltip = `Create + Release + Import ToC`
      type    = `Transparent`
      press   = client->_event( val = `TOC_CRI`
                                 t_arg = VALUE #( ( `${TRANSPORT}` ) ) ) ).

    cells->text( `{TOC_NUMBER}` ).
    cells->text( `{TOC_STATUS}` ).

    client->view_display( view->stringify( ) ).

  ENDMETHOD.


  METHOD popup_description.

    DATA(popup) = z2ui5_cl_xml_view=>factory_popup( ).
    DATA(dialog) = popup->dialog( title = |Description for new ToC ({ pending_transport })| ).

    dialog->simple_form( editable = abap_true
        )->content( `form`
            )->label( `Description for the Transport of Copies`
            )->text_area(
                value       = client->_bind_edit( custom_description )
                rows        = `4`
                width       = `40rem`
                placeholder = `Enter the description that should appear on the new ToC` ).

    dialog->buttons(
        )->button(
            text  = `Cancel`
            press = client->_event( `DESC_CANCEL` )
            type  = `Reject`
        )->button(
            text  = `Confirm`
            press = client->_event( `DESC_OK` )
            type  = `Emphasized` ).

    client->popup_display( popup->stringify( ) ).

  ENDMETHOD.

ENDCLASS.
