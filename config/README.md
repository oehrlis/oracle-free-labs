# Configuration

This folder contains all configuration for the **oracle-free-labs** project.  
Each subfolder corresponds to a service profile defined in `docker-compose.yml`.

## 📂 Subfolders

- **common/**  
  Shared assets across all services.  
  Includes reusable scripts (`scripts/`) and a Data Pump directory (`dpdump/`).

- **labdb/**  
  Configuration for the **labdb** service - an empty Oracle Free 23ai database for labs, engineering, and testing.  
  [Read more »](labdb/README.md)

- **odbrepo/**  
  Configuration for the **odbrepo** service - creates an EA Sparx repository using SQL scripts.  
  [Read more »](odbrepo/README.md)

- **odbseed/**  
  Configuration for the **odbseed** service - restores an EA Sparx repository from a PDB archive.  
  [Read more »](odbseed/README.md)

- **odbdemo/**  
  Configuration for the **odbdemo** service - sets up a complex EA demo repository from a PDB archive with additional setup steps.  
  [Read more »](odbdemo/README.md)

## 🛠 Conventions

- **setup/** - Scripts executed once on container initialization (schema creation, PDB restore).  
- **startup/** - Scripts executed each time the container starts (ACLs, grants, jobs).  
- **common/** is always mounted for all services.

## 🔒 Notes

- Avoid storing large PDB archives in Git - place them locally in the corresponding config folder.  
- Keep setup scripts **numbered** (e.g. `01_create_schema.sql`, `10_restore_pdb.sql`) to control execution order.  
- Git ignores sensitive or bulky runtime data (see project `.gitignore`).

