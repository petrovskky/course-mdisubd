CREATE OR REPLACE FUNCTION create_department(p_name TEXT)
RETURNS TABLE(department_id UUID, department_code VARCHAR(3))
LANGUAGE plpgsql
AS '
DECLARE
    v_id UUID;
    v_code VARCHAR(3);
BEGIN
    INSERT INTO departments (id, name, code)
    VALUES (
        gen_random_uuid(), 
        p_name, 
        LPAD(nextval(''department_code_seq'')::TEXT, 3, ''0'')
    )
    RETURNING id, code INTO v_id, v_code;
    
    department_id := v_id;
    department_code := v_code;
    
    RETURN NEXT;
    
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION ''Department with name "%" already exists'', p_name;
END;
';

CREATE OR REPLACE FUNCTION create_category(p_name TEXT)
RETURNS TABLE(category_id UUID, category_code VARCHAR(3))
LANGUAGE plpgsql
AS '
DECLARE
    v_id UUID;
    v_code VARCHAR(3);
BEGIN
    INSERT INTO categories (id, name, code)
    VALUES (
        gen_random_uuid(), 
        p_name, 
        LPAD(nextval(''category_code_seq'')::TEXT, 3, ''0'')
    )
    RETURNING id, code INTO v_id, v_code;
    
    category_id := v_id;
    category_code := v_code;
    
    RETURN NEXT;
    
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION ''Category with name "%" already exists'', p_name;
END;
';

CREATE OR REPLACE FUNCTION fn_generate_inventory_number(
    p_department_id UUID,
    p_category_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
AS '
DECLARE
    v_department_code TEXT;
    v_category_code TEXT;
    v_sequence INTEGER;
    v_inventory_number TEXT;
BEGIN
    SELECT code INTO v_department_code
    FROM departments WHERE id = p_department_id;
    
    IF v_department_code IS NULL THEN
        RAISE EXCEPTION ''Department code not found for department_id: %'', p_department_id;
    END IF;
    
    SELECT code INTO v_category_code
    FROM categories WHERE id = p_category_id;
    
    IF v_category_code IS NULL THEN
        RAISE EXCEPTION ''Category code not found for category_id: %'', p_category_id;
    END IF;
    
    SELECT COALESCE(MAX(sequence_number), 0) + 1 INTO v_sequence
    FROM assets 
    WHERE department_id = p_department_id 
    AND category_id = p_category_id;
    
    v_inventory_number := v_department_code || v_category_code || LPAD(v_sequence::TEXT, 5, ''0'');
    
    RETURN v_inventory_number;
END;
';

CREATE OR REPLACE FUNCTION create_asset(
    p_name TEXT,
    p_category_id UUID,
    p_location_id UUID,
    p_cost DECIMAL,
    p_acquisition_date DATE,
    p_service_life_months INTEGER,
    p_status TEXT,
    p_responsible_user_id UUID DEFAULT NULL,
    p_brand TEXT DEFAULT NULL,
    p_model TEXT DEFAULT NULL,
    p_serial_number TEXT DEFAULT NULL,
    p_photo_url TEXT DEFAULT NULL
)
RETURNS TABLE(asset_id UUID, asset_inventory_number TEXT, asset_sequence_number INTEGER)
LANGUAGE plpgsql
AS '
DECLARE
    v_department_id UUID;
    v_inventory_number TEXT;
    v_sequence INTEGER;
    v_asset_id UUID;
    v_category_exists BOOLEAN;
    v_location_exists BOOLEAN;
    v_user_exists BOOLEAN;
BEGIN
    SELECT EXISTS(SELECT 1 FROM categories WHERE id = p_category_id) INTO v_category_exists;
    IF NOT v_category_exists THEN
        RAISE EXCEPTION ''Category not found: %'', p_category_id;
    END IF;
    
    SELECT department_id INTO v_department_id
    FROM storage_locations WHERE id = p_location_id;
    
    IF v_department_id IS NULL THEN
        RAISE EXCEPTION ''Location not found: %'', p_location_id;
    END IF;
    
    IF p_status IN (''IN_STORAGE'', ''IN_USE'', ''IN_REPAIR'') THEN
        IF p_responsible_user_id IS NULL THEN
            RAISE EXCEPTION ''Responsible user is required for status: %'', p_status;
        END IF;
        
        SELECT EXISTS(SELECT 1 FROM users WHERE id = p_responsible_user_id) INTO v_user_exists;
        IF NOT v_user_exists THEN
            RAISE EXCEPTION ''Responsible user not found: %'', p_responsible_user_id;
        END IF;
        
    ELSIF p_status = ''INACTIVE'' THEN
        IF p_responsible_user_id IS NOT NULL THEN
            RAISE EXCEPTION ''Responsible user must be NULL for INACTIVE status'';
        END IF;
    ELSE
        RAISE EXCEPTION ''Invalid status: %'', p_status;
    END IF;
    
    v_inventory_number := fn_generate_inventory_number(v_department_id, p_category_id);
    
    v_sequence := CAST(SUBSTRING(v_inventory_number FROM 9 FOR 5) AS INTEGER);
    
    INSERT INTO assets (
        id, inventory_number, sequence_number, name, cost, status,
        acquisition_date, service_life_months, category_id, department_id,
        location_id, responsible_user_id, brand, model, serial_number, photo_url
    ) VALUES (
        gen_random_uuid(), v_inventory_number, v_sequence, p_name, p_cost, p_status,
        p_acquisition_date, p_service_life_months, p_category_id, v_department_id,
        p_location_id, p_responsible_user_id, p_brand, p_model, p_serial_number, p_photo_url
    )
    RETURNING id, inventory_number, sequence_number INTO v_asset_id, v_inventory_number, v_sequence;
    
    asset_id := v_asset_id;
    asset_inventory_number := v_inventory_number;
    asset_sequence_number := v_sequence;
    RETURN NEXT;
    
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION ''Asset with this inventory number already exists: %'', v_inventory_number;
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION ''Foreign key violation. Check category, department, location or user IDs'';
    WHEN check_violation THEN
        RAISE EXCEPTION ''Check constraint violation. Check status, cost or other constraints'';
END;
';

CREATE OR REPLACE FUNCTION confirm_transfer(
    p_transfer_id UUID,
    p_accepting_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS '
DECLARE
    v_asset_id UUID;
    v_current_responsible_user_id UUID;
    v_sender_user_id UUID;
    v_success BOOLEAN := false;
BEGIN
    SELECT t.asset_id, t.sender_user_id 
    INTO v_asset_id, v_sender_user_id
    FROM asset_transfers t
    WHERE t.id = p_transfer_id 
      AND t.receiver_user_id = p_accepting_user_id
      AND t.status = ''PENDING''
    FOR UPDATE;
    
    IF v_asset_id IS NULL THEN
        RETURN false;
    END IF;
    
    SELECT responsible_user_id INTO v_current_responsible_user_id
    FROM assets 
    WHERE id = v_asset_id 
    FOR UPDATE;
    
    IF v_current_responsible_user_id != v_sender_user_id THEN
        UPDATE asset_transfers 
        SET status = ''REJECTED'',
            receiver_responded_at = NOW()
        WHERE id = p_transfer_id;
        RETURN false;
    END IF;
    
    WITH updated_transfers AS (
        UPDATE asset_transfers 
        SET status = ''REJECTED'',
            receiver_responded_at = NOW()
        WHERE asset_id = v_asset_id 
          AND status = ''PENDING''
          AND id != p_transfer_id
        RETURNING id
    )
    UPDATE asset_transfers 
    SET status = ''CONFIRMED'',
        receiver_responded_at = NOW(),
        completed_at = NOW()
    WHERE id = p_transfer_id;
    
    UPDATE assets 
    SET responsible_user_id = p_accepting_user_id,
        status = ''IN_USE''
    WHERE id = v_asset_id;
    
    v_success := true;
    RETURN v_success;
    
EXCEPTION
    WHEN others THEN
        RAISE NOTICE ''Error in confirm_transfer: %'', SQLERRM;
        RETURN false;
END;
';

CREATE OR REPLACE FUNCTION create_inventory_check(
    p_name TEXT,
    p_storage_location_id UUID,
    p_created_by UUID,
    p_category_id UUID DEFAULT NULL,
    p_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS '
DECLARE
    v_check_id UUID;
    v_items_count INTEGER := 0;
    v_location_name TEXT;
    v_category_name TEXT;
BEGIN
    SELECT name INTO v_location_name
    FROM storage_locations
    WHERE id = p_storage_location_id;
    
    IF v_location_name IS NULL THEN
        RAISE EXCEPTION ''Storage location % not found'', p_storage_location_id;
    END IF;
    
    IF p_category_id IS NOT NULL THEN
        SELECT name INTO v_category_name
        FROM categories
        WHERE id = p_category_id;
        
        IF v_category_name IS NULL THEN
            RAISE EXCEPTION ''Category % not found'', p_category_id;
        END IF;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_created_by) THEN
        RAISE EXCEPTION ''User % not found'', p_created_by;
    END IF;
    
    v_check_id := gen_random_uuid();
    
    INSERT INTO inventory_checks (
        id, name, storage_location_id, category_id, 
        created_by, status, description
    ) VALUES (
        v_check_id,
        p_name,
        p_storage_location_id,
        p_category_id,
        p_created_by,
        ''IN_PROGRESS'',
        p_description
    );
    
    WITH inserted_items AS (
        INSERT INTO inventory_check_items (
            id, inventory_check_id, asset_id
        )
        SELECT 
            gen_random_uuid(),
            v_check_id,
            a.id
        FROM assets a
        WHERE a.location_id = p_storage_location_id
          AND (p_category_id IS NULL OR a.category_id = p_category_id)
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_items_count FROM inserted_items;
    
    RAISE NOTICE ''Created inventory check % for location ''''%'''' (% items)%'' ,
	    v_check_id,
	    v_location_name,
	    v_items_count,
	    CASE 
	        WHEN p_category_id IS NOT NULL 
	        THEN format('' in category ''''%s'''' '', v_category_name)
	        ELSE ''''
	    END;
    
    RETURN v_check_id;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE ''Error in create_inventory_check: %'', SQLERRM;
        RETURN NULL;
END;
';

CREATE OR REPLACE PROCEDURE sync_offline_operations(
    p_operations_json JSONB
)
LANGUAGE plpgsql
AS '
DECLARE
    rec JSONB;
    v_op_id UUID;
    v_op_type TEXT;
    v_table TEXT;
    v_data JSONB;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(p_operations_json)
    LOOP
        v_op_id := (rec->>''id'')::UUID;
        v_op_type := rec->>''operation_type'';
        v_table := rec->>''table_name'';
        v_data := rec->''data'';

        BEGIN
            CASE v_table
                WHEN ''categories'' THEN
                    IF v_op_type = ''INSERT'' THEN
                        INSERT INTO categories (id, code, name)
                        VALUES ((v_data->>''id'')::UUID, v_data->>''code'', v_data->>''name'')
                        ON CONFLICT (id) DO UPDATE SET
                            code = EXCLUDED.code,
                            name = EXCLUDED.name;
                    ELSIF v_op_type = ''UPDATE'' THEN
                        UPDATE categories SET code = v_data->>''code'', name = v_data->>''name''
                        WHERE id = (v_data->>''id'')::UUID;
                    ELSIF v_op_type = ''DELETE'' THEN
                        DELETE FROM categories WHERE id = (v_data->>''id'')::UUID;
                    END IF;

                WHEN ''departments'' THEN
                    IF v_op_type = ''INSERT'' THEN
                        INSERT INTO departments (id, code, name)
                        VALUES ((v_data->>''id'')::UUID, v_data->>''code'', v_data->>''name'')
                        ON CONFLICT (id) DO UPDATE SET
                            code = EXCLUDED.code,
                            name = EXCLUDED.name;
                    ELSIF v_op_type = ''UPDATE'' THEN
                        UPDATE departments SET code = v_data->>''code'', name = v_data->>''name''
                        WHERE id = (v_data->>''id'')::UUID;
                    ELSIF v_op_type = ''DELETE'' THEN
                        DELETE FROM departments WHERE id = (v_data->>''id'')::UUID;
                    END IF;

                WHEN ''assets'' THEN
                    IF v_op_type = ''INSERT'' THEN
                        INSERT INTO assets (
                            id, inventory_number, sequence_number, name, cost, status, 
                            acquisition_date, service_life_months, category_id, department_id, 
                            location_id, responsible_user_id, brand, model, serial_number, photo_url
                        ) VALUES (
                            (v_data->>''id'')::UUID,
                            v_data->>''inventory_number'',
                            (v_data->>''sequence_number'')::INTEGER,
                            v_data->>''name'',
                            (v_data->>''cost'')::DECIMAL,
                            v_data->>''status'',
                            (v_data->>''acquisition_date'')::DATE,
                            (v_data->>''service_life_months'')::INTEGER,
                            (v_data->>''category_id'')::UUID,
                            (v_data->>''department_id'')::UUID,
                            (v_data->>''location_id'')::UUID,
                            NULLIF(v_data->>''responsible_user_id'', '''') ::UUID,
                            v_data->>''brand'',
                            v_data->>''model'',
                            v_data->>''serial_number'',
                            v_data->>''photo_url''
                        )
                        ON CONFLICT (id) DO UPDATE SET
                            name = EXCLUDED.name,
                            cost = EXCLUDED.cost,
                            status = EXCLUDED.status,
                            department_id = EXCLUDED.department_id,
                            location_id = EXCLUDED.location_id,
                            responsible_user_id = EXCLUDED.responsible_user_id,
                            brand = EXCLUDED.brand,
                            model = EXCLUDED.model,
                            photo_url = EXCLUDED.photo_url;
                    ELSIF v_op_type = ''UPDATE'' THEN
                        UPDATE assets SET
                            name = v_data->>''name'',
                            cost = (v_data->>''cost'')::DECIMAL,
                            status = v_data->>''status'',
                            category_id = (v_data->>''category_id'')::UUID,
                            department_id = (v_data->>''department_id'')::UUID,
                            location_id = (v_data->>''location_id'')::UUID,
                            responsible_user_id = NULLIF(v_data->>''responsible_user_id'', '''') ::UUID,
                            brand = v_data->>''brand'',
                            model = v_data->>''model'',
                            serial_number = v_data->>''serial_number'',
                            photo_url = v_data->>''photo_url''
                        WHERE id = (v_data->>''id'')::UUID;
                    ELSIF v_op_type = ''DELETE'' THEN
                        UPDATE assets SET status = ''INACTIVE'', responsible_user_id = NULL
                        WHERE id = (v_data->>''id'')::UUID;
                    END IF;

                WHEN ''maintenance_requests'' THEN
                    IF v_op_type = ''INSERT'' THEN
                        INSERT INTO maintenance_requests (
                            id, asset_id, initiator_user_id, description, created_at, status, photo_url
                        ) VALUES (
                            (v_data->>''id'')::UUID,
                            (v_data->>''asset_id'')::UUID,
                            (v_data->>''initiator_user_id'')::UUID,
                            v_data->>''description'',
                            COALESCE((v_data->>''created_at'')::TIMESTAMPTZ, NOW()),
                            v_data->>''status'',
                            v_data->>''photo_url''
                        )
                        ON CONFLICT (id) DO UPDATE SET
                            description = EXCLUDED.description,
                            status = EXCLUDED.status,
                            photo_url = EXCLUDED.photo_url;
                    ELSIF v_op_type = ''UPDATE'' THEN
                        UPDATE maintenance_requests SET
                            description = v_data->>''description'',
                            status = v_data->>''status'',
                            photo_url = v_data->>''photo_url''
                        WHERE id = (v_data->>''id'')::UUID;
                    ELSIF v_op_type = ''DELETE'' THEN
                        DELETE FROM maintenance_requests WHERE id = (v_data->>''id'')::UUID;
                    END IF;

            END CASE;

        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE ''Error processing sync op % (%) for table %: %'', 
                v_op_id, v_op_type, v_table, SQLERRM;
        END;
    END LOOP;
END;
';

CREATE OR REPLACE FUNCTION get_report_data()
RETURNS TABLE (
    department_name TEXT,
    category_name TEXT,
    total_assets BIGINT,
    total_cost DECIMAL,
    count_in_use BIGINT,
    count_in_storage BIGINT,
    count_in_repair BIGINT,
    count_inactive BIGINT,
    dept_total_assets BIGINT,
    dept_total_cost DECIMAL,        
    category_cost_share NUMERIC,    
    category_rank_by_cost BIGINT    
)
LANGUAGE plpgsql
AS '
BEGIN
    RETURN QUERY
    WITH base_stats AS (
        SELECT 
            d.name AS d_name,
            c.name AS c_name,
            COUNT(a.id) AS asset_count,
            COALESCE(SUM(a.cost), 0) AS asset_cost,
            COUNT(a.id) FILTER (WHERE a.status = ''IN_USE'') AS in_use,
            COUNT(a.id) FILTER (WHERE a.status = ''IN_STORAGE'') AS in_storage,
            COUNT(a.id) FILTER (WHERE a.status = ''IN_REPAIR'') AS in_repair,
            COUNT(a.id) FILTER (WHERE a.status = ''INACTIVE'') AS inactive
        FROM assets a
        JOIN departments d ON a.department_id = d.id
        JOIN categories c ON a.category_id = c.id
        GROUP BY d.name, c.name
    )
    SELECT 
        d_name,
        c_name,
        asset_count,
        asset_cost,
        in_use,
        in_storage,
        in_repair,
        inactive,
        
        SUM(asset_count) OVER (PARTITION BY d_name)::BIGINT,
        
        SUM(asset_cost) OVER (PARTITION BY d_name),
        
        ROUND(
            (asset_cost / NULLIF(SUM(asset_cost) OVER (PARTITION BY d_name), 0) * 100), 
            2
        ),
        
        DENSE_RANK() OVER (PARTITION BY d_name ORDER BY asset_cost DESC)
        
    FROM base_stats
    ORDER BY d_name, asset_cost DESC;
END;
';