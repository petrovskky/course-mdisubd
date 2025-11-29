CREATE OR REPLACE FUNCTION fn_trg_log_asset_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS '
DECLARE
    v_changed_by UUID;
    v_record RECORD;
BEGIN
    IF (TG_OP = ''DELETE'') THEN
        v_record := OLD;
    ELSE
        v_record := NEW;
    END IF;

    BEGIN
        v_changed_by := current_setting(''app.current_user_id'', true)::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_changed_by := NULL;
    END;

    INSERT INTO asset_logs (
        id, asset_id, name, cost, status, acquisition_date, 
        category_id, location_id, responsible_user_id, 
        changed_at, changed_by, operation_type
    )
    VALUES (
        gen_random_uuid(),
        v_record.id,
        v_record.name,
        v_record.cost,
        v_record.status,
        v_record.acquisition_date,
        v_record.category_id,
        v_record.location_id,
        v_record.responsible_user_id,
        NOW(),
        v_changed_by,
        TG_OP
    );
    
    IF (TG_OP = ''DELETE'') THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
';

CREATE TRIGGER trg_assets_audit
AFTER INSERT OR UPDATE OR DELETE ON assets
FOR EACH ROW
EXECUTE FUNCTION fn_trg_log_asset_changes();

CREATE OR REPLACE FUNCTION fn_trg_log_user_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS '
DECLARE
    v_changed_by UUID;
    v_record RECORD;
BEGIN
    IF (TG_OP = ''DELETE'') THEN
        v_record := OLD;
    ELSE
        v_record := NEW;
    END IF;

    BEGIN
        v_changed_by := current_setting(''app.current_user_id'', true)::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_changed_by := NULL;
    END;

    INSERT INTO user_logs (
        id, user_id, username, phone, email, full_name, 
        role_id, department_id, changed_at, changed_by, operation_type
    )
    VALUES (
        gen_random_uuid(),
        v_record.id,
        v_record.username,
        v_record.phone,
        v_record.email,
        v_record.full_name,
        v_record.role_id,
        v_record.department_id,
        NOW(),
        v_changed_by,
        TG_OP
    );
    
    IF (TG_OP = ''DELETE'') THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
';

CREATE TRIGGER trg_users_audit
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW
EXECUTE FUNCTION fn_trg_log_user_changes();

CREATE OR REPLACE FUNCTION fn_trg_validate_asset_location()
RETURNS TRIGGER
LANGUAGE plpgsql
AS '
DECLARE
    v_location_dept_id UUID;
BEGIN
    SELECT department_id INTO v_location_dept_id
    FROM storage_locations
    WHERE id = NEW.location_id;

    IF v_location_dept_id IS NULL THEN
        RAISE EXCEPTION ''Location not found'';
    END IF;

    IF v_location_dept_id != NEW.department_id THEN
        RAISE EXCEPTION ''Asset location must belong to the asset department. Asset Dept: %, Location Dept: %'', 
            NEW.department_id, v_location_dept_id;
    END IF;

    RETURN NEW;
END;
';

CREATE TRIGGER trg_assets_check_location
BEFORE INSERT OR UPDATE OF location_id, department_id ON assets
FOR EACH ROW
EXECUTE FUNCTION fn_trg_validate_asset_location();

CREATE OR REPLACE FUNCTION fn_trg_auto_generate_inventory_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS '
BEGIN
    IF NEW.inventory_number IS NULL THEN
        NEW.inventory_number := fn_generate_inventory_number(NEW.department_id, NEW.category_id);
        NEW.sequence_number := CAST(SUBSTRING(NEW.inventory_number FROM 9 FOR 5) AS INTEGER);
    END IF;
    RETURN NEW;
END;
';

CREATE TRIGGER trg_assets_inventory_gen
BEFORE INSERT ON assets
FOR EACH ROW
EXECUTE FUNCTION fn_trg_auto_generate_inventory_number();

CREATE OR REPLACE FUNCTION fn_trg_maintenance_asset_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS '
BEGIN
    IF NEW.status = ''IN_PROGRESS'' AND (OLD.status IS DISTINCT FROM ''IN_PROGRESS'') THEN
        UPDATE assets 
        SET status = ''IN_REPAIR'' 
        WHERE id = NEW.asset_id;
    END IF;
    RETURN NEW;
END;
';

CREATE TRIGGER trg_maintenance_status_sync
AFTER INSERT OR UPDATE OF status ON maintenance_requests
FOR EACH ROW
EXECUTE FUNCTION fn_trg_maintenance_asset_status();

CREATE OR REPLACE FUNCTION fn_trg_process_transfer_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS '
DECLARE
    v_receiver_dept_id UUID;
    v_new_location_id UUID;
BEGIN
    IF (NEW.status = ''CONFIRMED'' AND OLD.status != ''CONFIRMED'') THEN
        
        SELECT department_id INTO v_receiver_dept_id 
        FROM users 
        WHERE id = NEW.receiver_user_id;

        SELECT id INTO v_new_location_id
        FROM storage_locations
        WHERE department_id = v_receiver_dept_id
        LIMIT 1;

        IF v_new_location_id IS NULL THEN
            RAISE EXCEPTION ''There is not a storage location in the department!'';
        END IF;

        UPDATE assets
        SET 
            responsible_user_id = NEW.receiver_user_id,
            department_id = v_receiver_dept_id,
            location_id = v_new_location_id,
            status = ''IN_USE''
        WHERE id = NEW.asset_id;

    END IF;

    RETURN NEW;
END;
';

CREATE TRIGGER trg_asset_transfers_update
AFTER INSERT OR UPDATE OF status ON asset_transfers
FOR EACH ROW
EXECUTE FUNCTION fn_trg_process_transfer_update();