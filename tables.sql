CREATE TABLE roles (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE departments (
    id UUID PRIMARY KEY,
	code VARCHAR(3) UNIQUE CHECK (code ~ '^[0-9]{3}$'),
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE storage_locations (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    department_id UUID NOT NULL,
	CONSTRAINT fk_storage_locations_department
		FOREIGN KEY (department_id)
		REFERENCES departments(id)
		ON DELETE RESTRICT,
	CONSTRAINT uq_storage_locations_name_department_id
		UNIQUE (name, department_id)
);

CREATE TABLE users (
    id UUID PRIMARY KEY,
	username TEXT NOT NULL UNIQUE,
	phone TEXT NOT NULL UNIQUE,
	email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    role_id UUID NOT NULL,
    department_id UUID NOT NULL,
	avatar_url TEXT,
	CONSTRAINT fk_users_role
		FOREIGN KEY (role_id)
		REFERENCES roles(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_users_department
		FOREIGN KEY (department_id)
		REFERENCES departments(id)
		ON DELETE RESTRICT
);

CREATE TABLE categories (
	id UUID PRIMARY KEY,
	code VARCHAR(3) UNIQUE CHECK (code ~ '^[0-9]{3}$'),
	name TEXT NOT NULL UNIQUE
);

CREATE TABLE assets (
	id UUID PRIMARY KEY,
	inventory_number TEXT NOT NULL UNIQUE,
	sequence_number INTEGER NOT NULL,
	name TEXT NOT NULL,
	cost DECIMAL NOT NULL CHECK (cost >= 0),
	status TEXT NOT NULL CHECK (status in ('IN_STORAGE', 'IN_USE', 'IN_REPAIR', 'INACTIVE')),
	acquisition_date DATE NOT NULL,
	service_life_months INTEGER CHECK (service_life_months > 0),
	category_id UUID NOT NULL,
	department_id UUID NOT NULL,
	location_id UUID NOT NULL,
	responsible_user_id UUID,
	brand TEXT,
	model TEXT,
	serial_number TEXT,
	photo_url TEXT,
	CONSTRAINT fk_assets_category
		FOREIGN KEY (category_id)
		REFERENCES categories(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_assets_department
		FOREIGN KEY (department_id)
		REFERENCES departments(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_assets_location
		FOREIGN KEY (location_id)
		REFERENCES storage_locations(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_assets_responsible_user
		FOREIGN KEY (responsible_user_id)
		REFERENCES users(id)
		ON DELETE RESTRICT,
	CONSTRAINT uq_assets_department_category_sequence 
    	UNIQUE (department_id, category_id, sequence_number)
);

CREATE TABLE asset_transfers (
	id UUID PRIMARY KEY,
	asset_id UUID NOT NULL,
	sender_user_id UUID NOT NULL,
	receiver_user_id UUID NOT NULL,
	status TEXT NOT NULL CHECK (status IN ('PENDING', 'CONFIRMED', 'REJECTED', 'CANCELLED')),
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	sender_cancelled_at TIMESTAMPTZ,
	receiver_responded_at TIMESTAMPTZ,
	CONSTRAINT fk_asset_transfers_asset
		FOREIGN KEY (asset_id)
		REFERENCES assets(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_asset_transfers_sender_user
		FOREIGN KEY (sender_user_id)
		REFERENCES users(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_asset_transfers_receiver_user
		FOREIGN KEY (receiver_user_id)
		REFERENCES users(id)
		ON DELETE RESTRICT,
	CONSTRAINT chk_sender_ne_receiver
        CHECK (sender_user_id != receiver_user_id),
	CONSTRAINT chk_transfer_status_logic 
    	CHECK (
        (status = 'PENDING' AND sender_cancelled_at IS NULL AND receiver_responded_at IS NULL) OR
        (status = 'CANCELLED' AND sender_cancelled_at IS NOT NULL AND receiver_responded_at IS NULL) OR
        (status = 'CONFIRMED' AND sender_cancelled_at IS NULL AND receiver_responded_at IS NOT NULL) OR
        (status = 'REJECTED' AND sender_cancelled_at IS NULL AND receiver_responded_at IS NOT NULL)
    )
);

CREATE TABLE maintenance_requests (
	id UUID PRIMARY KEY,
	asset_id UUID NOT NULL,
	initiator_user_id UUID NOT NULL,
	description TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	status TEXT NOT NULL CHECK (status IN ('OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
	photo_url TEXT,
	CONSTRAINT fk_maintenance_requests_asset
		FOREIGN KEY (asset_id)
		REFERENCES assets(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_initiator_user
		FOREIGN KEY (initiator_user_id)
		REFERENCES users(id)
		ON DELETE RESTRICT
);

CREATE TABLE inventory_checks (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
	storage_location_id UUID NOT NULL,
    category_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
    description TEXT,
    CONSTRAINT fk_inventory_checks_created_by
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT,
	CONSTRAINT fk_inventory_checks_storage_location
		FOREIGN KEY (storage_location_id)
		REFERENCES storage_locations(id)
		ON DELETE RESTRICT,
	CONSTRAINT fk_inventory_checks_category
		FOREIGN KEY (category_id)
		REFERENCES categories(id)
		ON DELETE RESTRICT
);

CREATE TABLE inventory_check_items (
    id UUID PRIMARY KEY,
    inventory_check_id UUID NOT NULL,
    asset_id UUID NOT NULL,
    result TEXT CHECK (result IN ('MATCH', 'MISMATCH', 'NOT_FOUND')),
	scanned_by UUID,
    scanned_at TIMESTAMPTZ,
    notes TEXT,
	photo_url TEXT,
    CONSTRAINT fk_inventory_check_items_inventory_check
		FOREIGN KEY (inventory_check_id) 
		REFERENCES inventory_checks(id)
		ON DELETE CASCADE,
    CONSTRAINT fk_inventory_check_items_asset 
		FOREIGN KEY (asset_id) 
		REFERENCES assets(id) 
		ON DELETE RESTRICT,
    CONSTRAINT fk_inventory_check_items_scanned_by
		FOREIGN KEY (scanned_by) 
		REFERENCES users(id) 
		ON DELETE RESTRICT,
    CONSTRAINT uq_inventory_check_items_check_asset 
		UNIQUE (inventory_check_id, asset_id)
);

CREATE TABLE notifications (
    id UUID PRIMARY KEY,
    receiver_user_id UUID NOT NULL,
    message TEXT NOT NULL,
    delivery_channel TEXT NOT NULL CHECK (delivery_channel IN ('PUSH', 'EMAIL')),
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_notifications_receiver_user
        FOREIGN KEY (receiver_user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

CREATE TABLE asset_logs (
	id UUID PRIMARY KEY,
	asset_id UUID NOT NULL,
	name TEXT,
    cost DECIMAL CHECK (cost >= 0),
    status TEXT CHECK (status in ('IN_STORAGE', 'IN_USE', 'IN_REPAIR', 'INACTIVE')),
    acquisition_date DATE,
    category_id UUID,
    location_id UUID,
    responsible_user_id UUID,
	operation_type TEXT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    changed_by UUID
);

CREATE TABLE user_logs (
    id UUID PRIMARY KEY,
	user_id UUID NOT NULL,
    username TEXT,
    phone TEXT,
    email TEXT,
    full_name TEXT,
    role_id UUID,
    department_id UUID,
	operation_type TEXT,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    changed_by UUID
);